# frozen_string_literal: true

module Entries
  # Wrapper for option chain data to provide No-Trade Engine methods
  class OptionChainWrapper
    attr_reader :chain_data, :index_key, :spot_price

    def initialize(chain_data:, index_key:)
      @index_key = index_key.to_s.upcase
      source = chain_data.is_a?(Hash) ? chain_data : {}
      @spot_price = extract_spot_price(source)
      # Handle different data formats: { oc: {...} }, { "oc" => {...} }, or direct chain data
      @chain_data = normalize_chain_data(source)
    end

    # Check if CE OI is rising
    # @return [Boolean]
    def ce_oi_rising?
      atm_ce = find_atm_option(:ce)
      oi_rising?(atm_ce)
    end

    # Check if PE OI is rising
    # @return [Boolean]
    def pe_oi_rising?
      atm_pe = find_atm_option(:pe)
      oi_rising?(atm_pe)
    end

    # Get ATM IV
    # @return [Float, nil]
    def atm_iv
      atm_ce = find_atm_option(:ce)
      atm_pe = find_atm_option(:pe)

      # Use average of CE and PE IV, or whichever is available
      instruments = [atm_ce, atm_pe].compact
      ivs = instruments.filter_map { |inst| inst&.dig('implied_volatility') }.map(&:to_f)
      return nil if ivs.empty?

      ivs.sum / ivs.size
    end

    # Check if IV is falling
    # @return [Boolean]
    def iv_falling?
      instruments = [find_atm_option(:ce), find_atm_option(:pe)].compact
      return false if instruments.empty?

      instruments.any? do |instrument|
        current_iv = instrument_iv(instrument)
        previous_iv = instrument_previous_iv(instrument)
        current_iv && previous_iv && current_iv < previous_iv
      end
    end

    # Check if spread is wide
    # @param hard_reject_threshold [Float] Hard reject threshold (default: uses index-specific)
    # @return [Boolean]
    def spread_wide?(hard_reject_threshold: nil)
      atm_ce = find_atm_option(:ce)
      atm_pe = find_atm_option(:pe)

      return false unless atm_ce || atm_pe

      # Get threshold from parameter or use index-specific default
      max_spread = hard_reject_threshold || get_index_spread_threshold

      # Check spreads for both CE and PE
      [atm_ce, atm_pe].each do |instrument|
        next unless instrument

        bid = instrument['top_bid_price']&.to_f || 0
        ask = instrument['top_ask_price']&.to_f || 0
        ltp = instrument['last_price']&.to_f || 0

        if bid.positive? && ask.positive? && ltp.positive?
          spread = ask - bid
          return true if spread > max_spread
        end
      end

      false
    end

    def get_index_spread_threshold
      thresholds = NoTradeThresholds.for_index(@index_key)
      thresholds[:spread_hard_reject] || 3.0
    end

    private

    def normalize_chain_data(source)
      if source.key?(:oc)
        source[:oc] || {}
      elsif source.key?('oc')
        source['oc'] || {}
      else
        source
      end
    end

    def extract_spot_price(source)
      source[:last_price]&.to_f || source['last_price']&.to_f
    end

    def find_atm_option(type)
      return nil unless chain_data.is_a?(Hash)

      strike_data = atm_strike_data
      return nil unless strike_data.is_a?(Hash)

      option = strike_data[type.to_s]
      option if option.is_a?(Hash) && option_last_price(option).positive?
    end

    def atm_strike_data
      structured = normalized_strike_rows
      return nil if structured.empty?

      target_strike = if spot_price&.positive?
                        spot_price
                      else
                        synthetic_spot(structured)
                      end

      structured.min_by { |row| [(row[:strike] - target_strike).abs, row[:strike]] }&.dig(:data)
    end

    def normalized_strike_rows
      chain_data.each_with_object([]) do |(strike_key, strike_data), rows|
        next unless strike_data.is_a?(Hash)

        strike = Float(strike_key)
        rows << { strike: strike, data: strike_data }
      rescue ArgumentError, TypeError
        next
      end
    end

    def synthetic_spot(structured)
      parity_candidates = structured.filter_map do |row|
        ce = row[:data]['ce']
        pe = row[:data]['pe']
        next unless ce.is_a?(Hash) && pe.is_a?(Hash)

        ce_ltp = option_last_price(ce)
        pe_ltp = option_last_price(pe)
        next unless ce_ltp.positive? && pe_ltp.positive?

        { strike: row[:strike], parity_gap: (ce_ltp - pe_ltp).abs }
      end
      parity_candidate = parity_candidates.min_by { |row| [row[:parity_gap], row[:strike]] }

      parity_candidate ? parity_candidate[:strike] : structured.min_by { |row| row[:strike] }[:strike]
    end

    def oi_rising?(instrument)
      return false unless instrument.is_a?(Hash)

      current_oi = instrument['oi'].to_i
      previous_oi = instrument['previous_oi'].to_i
      current_oi.positive? && previous_oi.positive? && current_oi > previous_oi
    end

    def instrument_iv(instrument)
      raw = instrument['implied_volatility'] || instrument['iv']
      value = raw&.to_f
      value if value&.positive?
    end

    def instrument_previous_iv(instrument)
      raw = instrument['previous_implied_volatility'] || instrument['previous_iv']
      value = raw&.to_f
      value if value&.positive?
    end

    def option_last_price(option)
      option['last_price']&.to_f || option['ltp']&.to_f || 0.0
    end
  end
end
