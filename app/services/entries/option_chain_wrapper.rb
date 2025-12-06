# frozen_string_literal: true

module Entries
  # Wrapper for option chain data to provide No-Trade Engine methods
  class OptionChainWrapper
    attr_reader :chain_data, :index_key

    def initialize(chain_data:, index_key:)
      @index_key = index_key.to_s.upcase
      # Handle different data formats: { oc: {...} } or direct oc hash
      @chain_data = if chain_data.is_a?(Hash) && chain_data.key?(:oc)
                      chain_data[:oc]
                    elsif chain_data.is_a?(Hash) && chain_data.key?('oc')
                      chain_data['oc']
                    else
                      chain_data || {}
                    end
    end

    # Check if CE OI is rising
    # @return [Boolean]
    def ce_oi_rising?
      return false unless chain_data.is_a?(Hash)

      ce_strikes = extract_ce_strikes
      return false if ce_strikes.size < 2

      # Compare last 2 OI values (if available in cache/history)
      # For now, use simple heuristic: check if ATM CE has OI
      atm_ce = find_atm_option(:ce)
      return false unless atm_ce

      # If we have historical data, compare; otherwise assume not rising
      # This is a simplified check - in production, you'd track OI history
      atm_ce['oi'].to_i.positive?
    end

    # Check if PE OI is rising
    # @return [Boolean]
    def pe_oi_rising?
      return false unless chain_data.is_a?(Hash)

      pe_strikes = extract_pe_strikes
      return false if pe_strikes.size < 2

      atm_pe = find_atm_option(:pe)
      return false unless atm_pe

      atm_pe['oi'].to_i.positive?
    end

    # Get ATM IV
    # @return [Float, nil]
    def atm_iv
      atm_ce = find_atm_option(:ce)
      atm_pe = find_atm_option(:pe)

      # Use average of CE and PE IV, or whichever is available
      ivs = [atm_ce&.dig('implied_volatility'), atm_pe&.dig('implied_volatility')].compact.map(&:to_f)
      return nil if ivs.empty?

      ivs.sum / ivs.size
    end

    # Check if IV is falling
    # @return [Boolean]
    def iv_falling?
      # Simplified check - in production, track IV history
      # For now, return false (assume stable)
      false
    end

    # Check if spread is wide
    # Uses index-specific thresholds:
    # NIFTY: >3 hard reject, >2 soft reject
    # SENSEX: >5 hard reject, >3 soft reject
    # BANKNIFTY: >3 hard reject, >2 soft reject
    # @param hard_reject [Boolean] If true, use hard reject threshold; if false, use soft reject threshold
    # @return [Boolean]
    def spread_wide?(hard_reject: true)
      atm_ce = find_atm_option(:ce)
      atm_pe = find_atm_option(:pe)

      return true unless atm_ce || atm_pe

      # Determine thresholds based on index
      if @index_key.include?('SENSEX')
        max_spread = hard_reject ? 5.0 : 3.0
      elsif @index_key.include?('BANK')
        max_spread = hard_reject ? 3.0 : 2.0
      else
        # NIFTY
        max_spread = hard_reject ? 3.0 : 2.0
      end

      # Check CE spread
      if atm_ce
        bid = atm_ce['top_bid_price']&.to_f || 0
        ask = atm_ce['top_ask_price']&.to_f || 0
        ltp = atm_ce['last_price']&.to_f || 0

        if bid.positive? && ask.positive? && ltp.positive?
          spread = ask - bid
          spread_ratio = spread / ltp

          return true if spread_ratio > max_spread
        end
      end

      # Check PE spread
      if atm_pe
        bid = atm_pe['top_bid_price']&.to_f || 0
        ask = atm_pe['top_ask_price']&.to_f || 0
        ltp = atm_pe['last_price']&.to_f || 0

        if bid.positive? && ask.positive? && ltp.positive?
          spread = ask - bid
          spread_ratio = spread / ltp

          return true if spread_ratio > max_spread
        end
      end

      false
    end

    private

    def extract_ce_strikes
      return [] unless chain_data.is_a?(Hash)

      chain_data.select { |_k, v| v.is_a?(Hash) && v.key?('ce') }
    end

    def extract_pe_strikes
      return [] unless chain_data.is_a?(Hash)

      chain_data.select { |_k, v| v.is_a?(Hash) && v.key?('pe') }
    end

    def find_atm_option(type)
      return nil unless chain_data.is_a?(Hash)

      # Find strike closest to current spot
      # For simplicity, use first available strike with the type
      chain_data.each_value do |strike_data|
        next unless strike_data.is_a?(Hash)

        option = strike_data[type.to_s]
        return option if option.is_a?(Hash) && option['last_price']&.to_f&.positive?
      end

      nil
    end
  end
end
