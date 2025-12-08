# frozen_string_literal: true

module Entries
  # No-Trade Engine: Validates market conditions before allowing entry
  # Blocks trades when multiple unfavorable conditions are present
  # Uses index-specific thresholds optimized for OPTIONS BUYING
  class NoTradeEngine
    Result = Struct.new(:allowed, :score, :reasons, keyword_init: true)

    # Validate context and determine if trade should be allowed
    # @param ctx [OpenStruct] Context from NoTradeContextBuilder
    # @return [Result] Validation result with allowed flag, score, and reasons
    def self.validate(ctx)
      reasons = []
      score = 0
      thresholds = ctx.thresholds || NoTradeThresholds::DEFAULT_THRESHOLDS

      # --- Trend Weakness (Index-Specific) ---
      # ADX threshold: NIFTY < 14, SENSEX < 12, BANKNIFTY < 16
      if ctx.adx_5m < thresholds[:adx_hard_reject]
        reasons << "Weak trend: ADX < #{thresholds[:adx_hard_reject]}"
        score += 1
      elsif ctx.adx_5m < thresholds[:adx_soft_reject]
        reasons << "Moderate trend: ADX #{ctx.adx_5m.round(1)} < #{thresholds[:adx_soft_reject]}"
        score += 0.5
      end

      # DI overlap threshold: NIFTY < 2.0, SENSEX < 1.5, BANKNIFTY < 2.5
      di_diff = (ctx.plus_di_5m - ctx.minus_di_5m).abs
      if di_diff < thresholds[:di_diff_hard_reject]
        reasons << "DI overlap: no directional strength (diff: #{di_diff.round(2)} < #{thresholds[:di_diff_hard_reject]})"
        score += 1
      elsif di_diff < thresholds[:di_diff_soft_reject]
        reasons << "Weak DI separation: #{di_diff.round(2)} < #{thresholds[:di_diff_soft_reject]}"
        score += 0.5
      end

      # --- Market Structure Failures ---
      # RELAXED: BOS check is now optional (0.5 instead of 1.0) to allow more trades
      # BOS is still useful but not a hard requirement
      unless ctx.bos_present
        reasons << 'No BOS in last 10m (relaxed)'
        score += 0.5
      end

      if ctx.in_opposite_ob
        reasons << 'Inside opposite OB'
        score += 1
      end

      if ctx.inside_fvg
        reasons << 'Inside opposing FVG'
        score += 1
      end

      # --- VWAP / AVWAP Filters (Index-Specific) ---
      # VWAP chop: NIFTY ±0.08% for 3+ candles, SENSEX ±0.06% for 2+ candles
      if ctx.vwap_chop
        reasons << "VWAP chop: price within ±#{thresholds[:vwap_chop_pct]}% for #{thresholds[:vwap_chop_candles]}+ candles"
        score += 1
      end

      if ctx.near_vwap
        reasons << "VWAP magnet zone (within ±#{thresholds[:vwap_chop_pct]}%)"
        score += 0.5
      end

      if ctx.trapped_between_vwap
        reasons << 'Trapped between VWAP & AVWAP'
        score += 1
      end

      # --- Volatility Filters (Index-Specific) ---
      # Range: NIFTY < 0.06%, SENSEX < 0.04%, BANKNIFTY < 0.08%
      if ctx.range_10m_pct < thresholds[:range_10m_hard_reject]
        reasons << "Low volatility: 10m range #{ctx.range_10m_pct.round(4)}% < #{thresholds[:range_10m_hard_reject]}%"
        score += 1
      elsif ctx.range_10m_pct < thresholds[:range_10m_soft_reject]
        reasons << "Moderate volatility: 10m range #{ctx.range_10m_pct.round(4)}% < #{thresholds[:range_10m_soft_reject]}%"
        score += 0.5
      end

      # ATR downtrend: NIFTY 5+ bars, SENSEX 3+ bars, BANKNIFTY 4+ bars
      if ctx.atr_downtrend
        reasons << "ATR decreasing (volatility compression for #{thresholds[:atr_downtrend_bars]}+ bars)"
        score += 1
      end

      # --- Option Chain Microstructure (Index-Specific) ---
      # OI trap: Both CE & PE OI rising with low range
      if ctx.oi_trap
        reasons << "OI trap: CE↑ & PE↑ & range < #{thresholds[:oi_trap_range_pct]}%"
        score += 1
      end

      # IV threshold: NIFTY < 9, SENSEX < 11, BANKNIFTY < 13
      if ctx.iv < thresholds[:iv_hard_reject]
        reasons << "IV too low: #{ctx.iv.round(2)} < #{thresholds[:iv_hard_reject]}"
        score += 1
      elsif ctx.iv < thresholds[:iv_soft_reject]
        reasons << "Low IV: #{ctx.iv.round(2)} < #{thresholds[:iv_soft_reject]}"
        score += 0.5
      end

      if ctx.iv_falling
        reasons << 'IV decreasing'
        score += 0.5
      end

      # Spread threshold: NIFTY > ₹3, SENSEX > ₹5, BANKNIFTY > ₹4
      if ctx.spread_wide
        reasons << "Wide bid-ask spread (> ₹#{thresholds[:spread_hard_reject]})"
        score += 1
      end

      # --- Candle Quality (Index-Specific) ---
      # Wick ratio: NIFTY > 2.2, SENSEX > 2.5, BANKNIFTY > 2.3
      if ctx.avg_wick_ratio > thresholds[:wick_ratio_hard_reject]
        reasons << "High wick ratio: #{ctx.avg_wick_ratio.round(2)} > #{thresholds[:wick_ratio_hard_reject]}"
        score += 1
      elsif ctx.avg_wick_ratio > thresholds[:wick_ratio_soft_reject]
        reasons << "Moderate wick ratio: #{ctx.avg_wick_ratio.round(2)} > #{thresholds[:wick_ratio_soft_reject]}"
        score += 0.5
      end

      # --- Time Windows ---
      if ctx.time_between.call('09:15', '09:18')
        reasons << 'Avoid first 3 minutes'
        score += 1
      end

      # Lunch-time check: Only block if ADX is weak during lunch hours
      # Use index-specific ADX soft reject threshold
      if ctx.time_between.call('11:20', '13:30') && ctx.adx_5m < thresholds[:adx_soft_reject]
        reasons << "Lunch-time theta zone (ADX < #{thresholds[:adx_soft_reject]})"
        score += 1
      end

      time_str = ctx.time.is_a?(String) ? ctx.time : ctx.time.strftime('%H:%M')
      if time_str > '15:05'
        reasons << 'Post 3:05 PM - theta crush'
        score += 1
      end

      # IMPROVED: Increased blocking threshold from 4 to 5 to be more selective
      # This allows trades with 4 or fewer unfavorable conditions
      # Goal: Better avg profit vs avg loss ratio by filtering more bad trades
      Result.new(
        allowed: score < 5,
        score: score.round(2),
        reasons: reasons
      )
    end
  end
end
