# frozen_string_literal: true

module Entries
  # Index-specific thresholds for No-Trade Engine
  # Optimized for OPTIONS BUYING based on volatility profiles, ATR norms,
  # mean reversion behavior, VWAP interaction patterns, and option-chain microstructure
  class NoTradeThresholds
    THRESHOLDS = {
      'NIFTY' => {
        # ADX (Trend Strength)
        adx_hard_reject: 14,
        adx_soft_reject: 18,
        # DI Separation (Directional Strength)
        di_diff_hard_reject: 2.0,
        di_diff_soft_reject: 3.0,
        # VWAP Chop Detection
        vwap_chop_pct: 0.08,
        vwap_chop_candles: 3,
        # Range / ATR Thresholds
        range_10m_hard_reject: 0.06,
        range_10m_soft_reject: 0.1,
        atr_downtrend_bars: 5,
        # Option Chain Microstructure
        iv_hard_reject: 9,
        iv_soft_reject: 11,
        oi_trap_range_pct: 0.08,
        # Spread Thresholds
        spread_hard_reject: 3,
        spread_soft_reject: 2,
        # Candle Behavior
        wick_ratio_hard_reject: 2.2,
        wick_ratio_soft_reject: 1.8
      },
      'SENSEX' => {
        # ADX (Trend Strength)
        adx_hard_reject: 12,
        adx_soft_reject: 16,
        # DI Separation (Directional Strength)
        di_diff_hard_reject: 1.5,
        di_diff_soft_reject: 2.5,
        # VWAP Chop Detection
        vwap_chop_pct: 0.06,
        vwap_chop_candles: 2,
        # Range / ATR Thresholds
        range_10m_hard_reject: 0.04,
        range_10m_soft_reject: 0.08,
        atr_downtrend_bars: 3,
        # Option Chain Microstructure
        iv_hard_reject: 11,
        iv_soft_reject: 13,
        oi_trap_range_pct: 0.06,
        # Spread Thresholds
        spread_hard_reject: 5,
        spread_soft_reject: 3,
        # Candle Behavior
        wick_ratio_hard_reject: 2.5,
        wick_ratio_soft_reject: 2.0
      },
      'BANKNIFTY' => {
        # ADX (Trend Strength) - BankNifty is more volatile, needs stronger trend
        adx_hard_reject: 16,
        adx_soft_reject: 20,
        # DI Separation (Directional Strength)
        di_diff_hard_reject: 2.5,
        di_diff_soft_reject: 3.5,
        # VWAP Chop Detection
        vwap_chop_pct: 0.1,
        vwap_chop_candles: 3,
        # Range / ATR Thresholds
        range_10m_hard_reject: 0.08,
        range_10m_soft_reject: 0.12,
        atr_downtrend_bars: 4,
        # Option Chain Microstructure
        iv_hard_reject: 13,
        iv_soft_reject: 16,
        oi_trap_range_pct: 0.1,
        # Spread Thresholds
        spread_hard_reject: 4,
        spread_soft_reject: 3,
        # Candle Behavior
        wick_ratio_hard_reject: 2.3,
        wick_ratio_soft_reject: 1.9
      }
    }.freeze

    DEFAULT_THRESHOLDS = THRESHOLDS['NIFTY'].freeze

    class << self
      # Get thresholds for a specific index
      # @param index_key [String] Index key (e.g., "NIFTY", "SENSEX", "BANKNIFTY")
      # @return [Hash] Threshold configuration
      def for_index(index_key)
        key = normalize_index_key(index_key)
        THRESHOLDS[key] || DEFAULT_THRESHOLDS
      end

      private

      def normalize_index_key(index_key)
        return 'NIFTY' unless index_key

        key = index_key.to_s.upcase
        # Handle variations
        case key
        when /NIFTY/
          'NIFTY'
        when /SENSEX/
          'SENSEX'
        when /BANK/
          'BANKNIFTY'
        else
          'NIFTY'
        end
      end
    end
  end
end
