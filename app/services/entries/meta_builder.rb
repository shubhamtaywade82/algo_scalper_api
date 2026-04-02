# frozen_string_literal: true

module Entries
  class MetaBuilder
    SUPERTREND_CONTRACT = 'supertrend_machine_v1'

    def self.call(meta_hash, bos_context, entry_metadata, entry_price:, quantity:)
      return unless bos_context

      contract = entry_metadata.is_a?(Hash) ? entry_metadata[:entry_contract].to_s : ''
      sl_decimal = supertrend_sl_decimal
      premium_r = entry_price.to_f * sl_decimal
      qty_int = SafeNumeric.to_non_negative_integer(quantity)
      entry_risk_rupees = premium_r * qty_int

      if contract == SUPERTREND_CONTRACT
        origin_price = nil
        entry_underlying_price = entry_metadata.is_a?(Hash) ? entry_metadata[:entry_underlying_price] : nil
      else
        origin_price = bos_context[:origin_swing][:price].to_f
        entry_underlying_price = bos_context[:entry_underlying_price]
      end

      premium_stop = entry_price.to_f - premium_r
      premium_target = entry_price.to_f + premium_r

      meta_hash[:structure_invalidation_price] = origin_price if origin_price.present?
      meta_hash[:entry_premium] = entry_price.to_f
      meta_hash[:peak_premium] = entry_price.to_f
      meta_hash[:peak_premium_at] = Time.current.iso8601
      meta_hash[:entry_risk_rupees] = entry_risk_rupees
      meta_hash[:premium_stop_price] = premium_stop
      meta_hash[:initial_sl_pct] = safe_initial_sl_pct(premium_r, entry_price.to_f)
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

    def self.supertrend_sl_decimal
      value = AlgoConfig.fetch.dig(:risk, :sl_pct).to_f
      value.positive? ? value : 0.12
    rescue StandardError
      0.12
    end

    def self.safe_initial_sl_pct(premium_r, entry_price_f)
      return 0.0 unless entry_price_f.finite? && entry_price_f.positive?

      ratio = premium_r / entry_price_f * 100.0
      ratio.finite? ? ratio.round(2) : 0.0
    end
  end
end
