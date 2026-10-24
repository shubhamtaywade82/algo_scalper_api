# frozen_string_literal: true

module Entries
  class MetaBuilder
    SUPERTREND_CONTRACT = 'supertrend_machine_v1'

    def self.call(meta_hash, bos_context, entry_metadata, entry_price:, quantity:)
      return unless bos_context

      contract = entry_metadata.is_a?(Hash) ? entry_metadata[:entry_contract].to_s : ''

      # Strict inputs (error-handling review 2026-09, wave 2): these values pin
      # the position's stop/target/risk metadata for its whole life. Garbage
      # used to coerce to 0 and produce NaN stops or a fabricated ₹0 risk.
      entry_price_f = positive_price!(entry_price, 'entry_price')
      qty_int = Orders::Quantity.resolve!(quantity, context: 'MetaBuilder entry risk sizing')

      sl_decimal = supertrend_sl_decimal
      premium_r = entry_price_f * sl_decimal
      entry_risk_rupees = premium_r * qty_int

      if contract == SUPERTREND_CONTRACT
        # Supertrend direct entries carry no BOS structure risk: no structure
        # invalidation price is pinned (premium risk covers it).
        origin_price = nil
        entry_underlying_price = entry_metadata.is_a?(Hash) ? entry_metadata[:entry_underlying_price] : nil
      else
        # Non-supertrend entries carry their structural stop in the BOS origin
        # swing. A missing/zero swing price used to be written into tracker meta
        # as structure_invalidation_price = 0.0, silently disabling
        # structure-invalidation exits for the life of the trade.
        swing_price = bos_context.dig(:origin_swing, :price)
        origin_price = positive_price!(swing_price, 'bos_context[:origin_swing][:price]')
        entry_underlying_price = bos_context[:entry_underlying_price]
      end

      premium_stop = entry_price_f - premium_r
      premium_target = entry_price_f + premium_r

      meta_hash[:structure_invalidation_price] = origin_price if origin_price.present?
      meta_hash[:entry_premium] = entry_price_f
      meta_hash[:peak_premium] = entry_price_f
      meta_hash[:peak_premium_at] = Time.current.iso8601
      meta_hash[:entry_risk_rupees] = entry_risk_rupees
      meta_hash[:premium_stop_price] = premium_stop
      meta_hash[:initial_sl_pct] = safe_initial_sl_pct(premium_r, entry_price_f)
      meta_hash[:premium_target_price] = premium_target
      meta_hash[:entry_underlying_price] = entry_underlying_price
      meta_hash[:bos_confirmed_at] = bos_context[:confirmed_at]&.iso8601
      meta_hash[:bos_origin_index] = bos_context[:origin_swing][:index]
      meta_hash[:bos_timeframe] = bos_context[:timeframe]
      meta_hash[:bos_direction] = bos_context[:direction]
      meta_hash[:bos_id] = bos_context[:bos_id]

      if entry_metadata.is_a?(Hash)
        meta_hash[:bos_age_at_entry] = entry_metadata[:bos_age_at_entry] if entry_metadata.key?(:bos_age_at_entry)
        meta_hash[:retrace_pct] = entry_metadata[:retrace_pct] if entry_metadata.key?(:retrace_pct)
        meta_hash[:pullback_candles] = entry_metadata[:pullback_candles] if entry_metadata.key?(:pullback_candles)
        meta_hash[:entry_distance_r] = entry_metadata[:entry_distance_r] if entry_metadata.key?(:entry_distance_r)
        meta_hash[:entry_tf] = entry_metadata[:entry_tf]
        meta_hash[:htf_tf] = entry_metadata[:htf_tf]
      end
    end

    # Supertrend direct entries derive premium risk from the configured SL %.
    #
    # Error-handling review 2026-09 (wave 2): a missing/corrupt risk.sl_pct
    # used to silently become 0.12 — a WIDER stop than the shipped 0.10, with
    # no signal. The value is now mandatory.
    #
    # @return [Float]
    # @raise [Errors::ConfigurationError] when risk.sl_pct is missing, non-positive or non-finite
    def self.supertrend_sl_decimal
      raw = AlgoConfig.fetch.dig(:risk, :sl_pct)
      value = raw.to_f

      unless raw.present? && value.finite? && value.positive?
        raise Errors::ConfigurationError,
              "risk.sl_pct must be a positive number — got #{raw.inspect}; refusing to assume a stop-loss percentage"
      end

      value
    end

    def self.safe_initial_sl_pct(premium_r, entry_price_f)
      return 0.0 unless entry_price_f.finite? && entry_price_f.positive?

      ratio = premium_r / entry_price_f * 100.0
      ratio.finite? ? ratio.round(2) : 0.0
    end

    # @raise [Errors::InvalidPrice] when the value is not a positive finite number
    def self.positive_price!(value, label)
      price = value.to_f
      unless value.present? && price.finite? && price.positive?
        raise Errors::InvalidPrice, "#{label} must be a positive number — got #{value.inspect}"
      end

      price
    end
  end
end
