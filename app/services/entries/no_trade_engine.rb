# frozen_string_literal: true

module Entries
  # No-Trade Engine: Validates market conditions before allowing entry
  # Blocks trades when multiple unfavorable conditions are present
  class NoTradeEngine
    Result = Struct.new(:allowed, :score, :reasons, keyword_init: true)

    # Validate context and determine if trade should be allowed
    # @param ctx [OpenStruct] Context from NoTradeContextBuilder
    # @return [Result] Validation result with allowed flag, score, and reasons
    def self.validate(ctx)
      reasons = []
      score = 0

      # --- Trend Weakness ---
      if ctx.adx_5m < 18
        reasons << 'Weak trend: ADX < 18'
        score += 1
      end

      di_diff = (ctx.plus_di_5m - ctx.minus_di_5m).abs
      if di_diff < 3
        reasons << 'DI overlap: no directional strength'
        score += 1
      end

      # --- Market Structure Failures ---
      unless ctx.bos_present
        reasons << 'No BOS in last 10m'
        score += 1
      end

      if ctx.in_opposite_ob
        reasons << 'Inside opposite OB'
        score += 1
      end

      if ctx.inside_fvg
        reasons << 'Inside opposing FVG'
        score += 1
      end

      # --- VWAP / AVWAP Filters ---
      if ctx.near_vwap
        reasons << 'VWAP magnet zone'
        score += 1
      end

      if ctx.trapped_between_vwap
        reasons << 'Trapped between VWAP & AVWAP'
        score += 1
      end

      # --- Volatility Filters ---
      if ctx.range_10m_pct < 0.1
        reasons << 'Low volatility: 10m range < 0.1%'
        score += 1
      end

      if ctx.atr_downtrend
        reasons << 'ATR decreasing (volatility compression)'
        score += 1
      end

      # --- Option Chain Microstructure ---
      if ctx.ce_oi_up && ctx.pe_oi_up
        reasons << 'Both CE & PE OI rising (writers controlling)'
        score += 1
      end

      if ctx.iv < ctx.min_iv_threshold
        reasons << "IV too low (#{ctx.iv.round(2)} < #{ctx.min_iv_threshold})"
        score += 1
      end

      if ctx.iv_falling
        reasons << 'IV decreasing'
        score += 1
      end

      if ctx.spread_wide
        reasons << 'Wide bid-ask spread'
        score += 1
      end

      # --- Candle Quality ---
      if ctx.avg_wick_ratio > 1.8
        reasons << "High wick ratio (#{ctx.avg_wick_ratio.round(2)})"
        score += 1
      end

      # --- Time Windows ---
      if ctx.time_between.call('09:15', '09:18')
        reasons << 'Avoid first 3 minutes'
        score += 1
      end

      if ctx.time_between.call('11:20', '13:30') && ctx.adx_5m < 25
        reasons << 'Lunch-time theta zone'
        score += 1
      end

      time_str = ctx.time.is_a?(String) ? ctx.time : ctx.time.strftime('%H:%M')
      if time_str > '15:05'
        reasons << 'Post 3:05 PM - theta crush'
        score += 1
      end

      Result.new(
        allowed: score < 3,
        score: score,
        reasons: reasons
      )
    end
  end
end
