# frozen_string_literal: true

# Test fixtures for No-Trade Engine threshold conditions
# These fixtures represent real-world scenarios for each threshold condition
# Optimized for NIFTY, SENSEX, and BANKNIFTY based on volatility profiles

module NoTradeThresholdFixtures
  # Base context with all conditions passing
  def self.base_context(index_key: 'NIFTY')
    thresholds = Entries::NoTradeThresholds.for_index(index_key)

    OpenStruct.new(
      index_key: index_key,
      thresholds: thresholds,
      adx_5m: thresholds[:adx_soft_reject] + 5, # Strong trend
      plus_di_5m: 30,
      minus_di_5m: 10,
      bos_present: true,
      in_opposite_ob: false,
      inside_fvg: false,
      near_vwap: false,
      vwap_chop: false,
      trapped_between_vwap: false,
      range_10m_pct: thresholds[:range_10m_soft_reject] + 0.05,
      atr_downtrend: false,
      ce_oi_up: false,
      pe_oi_up: false,
      iv: thresholds[:iv_soft_reject] + 2,
      iv_falling: false,
      oi_trap: false,
      spread_wide: false,
      avg_wick_ratio: thresholds[:wick_ratio_soft_reject] - 0.3,
      time: '10:30',
      time_between: ->(_start, _end) { false }
    )
  end

  # NIFTY-specific fixtures
  module Nifty
    # ADX Hard Reject: ADX < 14
    def self.adx_hard_reject
      ctx = base_context(index_key: 'NIFTY')
      ctx.adx_5m = 13
      ctx
    end

    # ADX Soft Reject: ADX 14-18
    def self.adx_soft_reject
      ctx = base_context(index_key: 'NIFTY')
      ctx.adx_5m = 16
      ctx
    end

    # DI Hard Reject: DI diff < 2.0
    def self.di_hard_reject
      ctx = base_context(index_key: 'NIFTY')
      ctx.plus_di_5m = 20
      ctx.minus_di_5m = 19.5 # Diff = 0.5
      ctx
    end

    # VWAP Chop: ±0.08% for 3+ candles
    def self.vwap_chop
      ctx = base_context(index_key: 'NIFTY')
      ctx.vwap_chop = true
      ctx
    end

    # Range Hard Reject: < 0.06%
    def self.range_hard_reject
      ctx = base_context(index_key: 'NIFTY')
      ctx.range_10m_pct = 0.05
      ctx
    end

    # ATR Downtrend: 5+ bars
    def self.atr_downtrend
      ctx = base_context(index_key: 'NIFTY')
      ctx.atr_downtrend = true
      ctx
    end

    # IV Hard Reject: < 9
    def self.iv_hard_reject
      ctx = base_context(index_key: 'NIFTY')
      ctx.iv = 8.5
      ctx
    end

    # OI Trap: CE↑ & PE↑ & range < 0.08%
    def self.oi_trap
      ctx = base_context(index_key: 'NIFTY')
      ctx.ce_oi_up = true
      ctx.pe_oi_up = true
      ctx.range_10m_pct = 0.07
      ctx.oi_trap = true
      ctx
    end

    # Spread Hard Reject: > ₹3
    def self.spread_hard_reject
      ctx = base_context(index_key: 'NIFTY')
      ctx.spread_wide = true
      ctx
    end

    # Wick Ratio Hard Reject: > 2.2
    def self.wick_ratio_hard_reject
      ctx = base_context(index_key: 'NIFTY')
      ctx.avg_wick_ratio = 2.3
      ctx
    end
  end

  # SENSEX-specific fixtures
  module Sensex
    # ADX Hard Reject: ADX < 12
    def self.adx_hard_reject
      ctx = base_context(index_key: 'SENSEX')
      ctx.adx_5m = 11
      ctx
    end

    # DI Hard Reject: DI diff < 1.5
    def self.di_hard_reject
      ctx = base_context(index_key: 'SENSEX')
      ctx.plus_di_5m = 20
      ctx.minus_di_5m = 19.0 # Diff = 1.0
      ctx
    end

    # VWAP Chop: ±0.06% for 2+ candles
    def self.vwap_chop
      ctx = base_context(index_key: 'SENSEX')
      ctx.vwap_chop = true
      ctx
    end

    # Range Hard Reject: < 0.04%
    def self.range_hard_reject
      ctx = base_context(index_key: 'SENSEX')
      ctx.range_10m_pct = 0.03
      ctx
    end

    # ATR Downtrend: 3+ bars
    def self.atr_downtrend
      ctx = base_context(index_key: 'SENSEX')
      ctx.atr_downtrend = true
      ctx
    end

    # IV Hard Reject: < 11
    def self.iv_hard_reject
      ctx = base_context(index_key: 'SENSEX')
      ctx.iv = 10.5
      ctx
    end

    # OI Trap: CE↑ & PE↑ & range < 0.06%
    def self.oi_trap
      ctx = base_context(index_key: 'SENSEX')
      ctx.ce_oi_up = true
      ctx.pe_oi_up = true
      ctx.range_10m_pct = 0.05
      ctx.oi_trap = true
      ctx
    end

    # Spread Hard Reject: > ₹5
    def self.spread_hard_reject
      ctx = base_context(index_key: 'SENSEX')
      ctx.spread_wide = true
      ctx
    end

    # Wick Ratio Hard Reject: > 2.5
    def self.wick_ratio_hard_reject
      ctx = base_context(index_key: 'SENSEX')
      ctx.avg_wick_ratio = 2.6
      ctx
    end
  end

  # BANKNIFTY-specific fixtures
  module BankNifty
    # ADX Hard Reject: ADX < 16
    def self.adx_hard_reject
      ctx = base_context(index_key: 'BANKNIFTY')
      ctx.adx_5m = 15
      ctx
    end

    # DI Hard Reject: DI diff < 2.5
    def self.di_hard_reject
      ctx = base_context(index_key: 'BANKNIFTY')
      ctx.plus_di_5m = 20
      ctx.minus_di_5m = 18.0 # Diff = 2.0
      ctx
    end

    # VWAP Chop: ±0.1% for 3+ candles
    def self.vwap_chop
      ctx = base_context(index_key: 'BANKNIFTY')
      ctx.vwap_chop = true
      ctx
    end

    # Range Hard Reject: < 0.08%
    def self.range_hard_reject
      ctx = base_context(index_key: 'BANKNIFTY')
      ctx.range_10m_pct = 0.07
      ctx
    end

    # ATR Downtrend: 4+ bars
    def self.atr_downtrend
      ctx = base_context(index_key: 'BANKNIFTY')
      ctx.atr_downtrend = true
      ctx
    end

    # IV Hard Reject: < 13
    def self.iv_hard_reject
      ctx = base_context(index_key: 'BANKNIFTY')
      ctx.iv = 12.5
      ctx
    end

    # OI Trap: CE↑ & PE↑ & range < 0.1%
    def self.oi_trap
      ctx = base_context(index_key: 'BANKNIFTY')
      ctx.ce_oi_up = true
      ctx.pe_oi_up = true
      ctx.range_10m_pct = 0.09
      ctx.oi_trap = true
      ctx
    end

    # Spread Hard Reject: > ₹4
    def self.spread_hard_reject
      ctx = base_context(index_key: 'BANKNIFTY')
      ctx.spread_wide = true
      ctx
    end

    # Wick Ratio Hard Reject: > 2.3
    def self.wick_ratio_hard_reject
      ctx = base_context(index_key: 'BANKNIFTY')
      ctx.avg_wick_ratio = 2.4
      ctx
    end
  end

  # Combined scenarios (multiple conditions)
  module Combined
    # Worst case: All conditions failing
    def self.all_conditions_failing(index_key: 'NIFTY')
      thresholds = Entries::NoTradeThresholds.for_index(index_key)

      OpenStruct.new(
        index_key: index_key,
        thresholds: thresholds,
        adx_5m: thresholds[:adx_hard_reject] - 1,
        plus_di_5m: 20,
        minus_di_5m: 19.5,
        bos_present: false,
        in_opposite_ob: true,
        inside_fvg: true,
        near_vwap: true,
        vwap_chop: true,
        trapped_between_vwap: true,
        range_10m_pct: thresholds[:range_10m_hard_reject] - 0.01,
        atr_downtrend: true,
        ce_oi_up: true,
        pe_oi_up: true,
        iv: thresholds[:iv_hard_reject] - 1,
        iv_falling: true,
        oi_trap: true,
        spread_wide: true,
        avg_wick_ratio: thresholds[:wick_ratio_hard_reject] + 0.5,
        time: '09:16',
        time_between: ->(start, _end) { start == '09:15' }
      )
    end

    # Edge case: Score exactly at threshold (2.5)
    def self.score_at_threshold(index_key: 'NIFTY')
      thresholds = Entries::NoTradeThresholds.for_index(index_key)

      OpenStruct.new(
        index_key: index_key,
        thresholds: thresholds,
        adx_5m: thresholds[:adx_hard_reject] - 1,
        plus_di_5m: 20,
        minus_di_5m: 19.5,
        bos_present: false,
        in_opposite_ob: false,
        inside_fvg: false,
        near_vwap: false,
        vwap_chop: false,
        trapped_between_vwap: false,
        range_10m_pct: thresholds[:range_10m_soft_reject] + 0.01,
        atr_downtrend: false,
        ce_oi_up: false,
        pe_oi_up: false,
        iv: thresholds[:iv_soft_reject] + 1,
        iv_falling: false,
        oi_trap: false,
        spread_wide: false,
        avg_wick_ratio: thresholds[:wick_ratio_soft_reject] - 0.1,
        time: '10:30',
        time_between: ->(_start, _end) { false }
      )
    end
  end
end
