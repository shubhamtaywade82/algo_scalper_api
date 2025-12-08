# frozen_string_literal: true

module Entries
  # Index-specific thresholds for No-Trade Engine
  # Optimized for OPTIONS BUYING based on volatility profiles, ATR norms,
  # mean reversion behavior, VWAP interaction patterns, and option-chain microstructure
  class NoTradeThresholds
    THRESHOLDS = {
      'NIFTY' => {
        # ADX (Trend Strength) - FURTHER RELAXED: Lower thresholds to improve profit/loss ratio
        adx_hard_reject: 10,  # Was 12, now 10 (allow weaker trends)
        adx_soft_reject: 14,  # Was 16, now 14
        # DI Separation (Directional Strength) - FURTHER RELAXED: Lower thresholds
        di_diff_hard_reject: 1.2,  # Was 1.5, now 1.2 (allow more overlap)
        di_diff_soft_reject: 2.0,  # Was 2.5, now 2.0
        # VWAP Chop Detection
        vwap_chop_pct: 0.08,
        vwap_chop_candles: 3,
        # Range / ATR Thresholds - RELAXED: Lower thresholds to allow more trades
        range_10m_hard_reject: 0.04,  # Was 0.06, now 0.04
        range_10m_soft_reject: 0.08,   # Was 0.1, now 0.08
        atr_downtrend_bars: 5,
        # Option Chain Microstructure - RELAXED: Lower IV thresholds
        iv_hard_reject: 7,   # Was 9, now 7
        iv_soft_reject: 9,   # Was 11, now 9
        oi_trap_range_pct: 0.08,
        # Spread Thresholds - RELAXED: Higher spread tolerance
        spread_hard_reject: 4,  # Was 3, now 4 (₹4 instead of ₹3)
        spread_soft_reject: 3,  # Was 2, now 3
        # Candle Behavior
        wick_ratio_hard_reject: 2.2,
        wick_ratio_soft_reject: 1.8
      },
      'SENSEX' => {
        # ADX (Trend Strength) - RELAXED: Lower thresholds
        adx_hard_reject: 10,  # Was 12, now 10
        adx_soft_reject: 14,  # Was 16, now 14
        # DI Separation (Directional Strength) - RELAXED: Lower thresholds
        di_diff_hard_reject: 1.2,  # Was 1.5, now 1.2
        di_diff_soft_reject: 2.0,  # Was 2.5, now 2.0
        # VWAP Chop Detection
        vwap_chop_pct: 0.06,
        vwap_chop_candles: 2,
        # Range / ATR Thresholds - RELAXED: Lower thresholds
        range_10m_hard_reject: 0.03,  # Was 0.04, now 0.03
        range_10m_soft_reject: 0.06,  # Was 0.08, now 0.06
        atr_downtrend_bars: 3,
        # Option Chain Microstructure - RELAXED: Lower IV thresholds
        iv_hard_reject: 9,   # Was 11, now 9
        iv_soft_reject: 11,  # Was 13, now 11
        oi_trap_range_pct: 0.06,
        # Spread Thresholds
        spread_hard_reject: 5,
        spread_soft_reject: 3,
        # Candle Behavior
        wick_ratio_hard_reject: 2.5,
        wick_ratio_soft_reject: 2.0
      },
      'BANKNIFTY' => {
        # ADX (Trend Strength) - RELAXED: Lower thresholds (BankNifty is more volatile)
        adx_hard_reject: 14,  # Was 16, now 14
        adx_soft_reject: 18,  # Was 20, now 18
        # DI Separation (Directional Strength) - RELAXED: Lower thresholds
        di_diff_hard_reject: 2.0,  # Was 2.5, now 2.0
        di_diff_soft_reject: 3.0,  # Was 3.5, now 3.0
        # VWAP Chop Detection
        vwap_chop_pct: 0.1,
        vwap_chop_candles: 3,
        # Range / ATR Thresholds - RELAXED: Lower thresholds
        range_10m_hard_reject: 0.06,  # Was 0.08, now 0.06
        range_10m_soft_reject: 0.10,  # Was 0.12, now 0.10
        atr_downtrend_bars: 4,
        # Option Chain Microstructure - RELAXED: Lower IV thresholds
        iv_hard_reject: 11,  # Was 13, now 11
        iv_soft_reject: 14,  # Was 16, now 14
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

