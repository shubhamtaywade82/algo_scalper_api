# frozen_string_literal: true

module Entries
  # No-Trade Engine: Validates market conditions before allowing entry
  # Blocks trades when multiple unfavorable conditions are present
  #
  # Index-specific thresholds optimized for OPTIONS BUYING:
  # - NIFTY: Requires stronger trend filters due to choppy nature
  # - SENSEX: Allows slightly looser trend filters but tighter spread filters
  #
  # NIFTY THRESHOLDS:
  #   ADX reject <14, soft 14-18
  #   DI reject <2
  #   VWAP chop: ±0.08% for 3+ candles
  #   Range reject <0.06%, soft <0.1%
  #   IV reject <9, soft 9-11
  #   OI trap: CE↑ PE↑ & range <0.08%
  #   Spread reject >3, soft >2
  #   Wick reject >2.2
  #
  # SENSEX THRESHOLDS:
  #   ADX reject <12, soft 12-16
  #   DI reject <1.5
  #   VWAP chop: ±0.06% for 2+ candles
  #   Range reject <0.04%, soft <0.08%
  #   IV reject <11, soft 11-13
  #   OI trap: CE↑ PE↑ & range <0.06%
  #   Spread reject >5, soft >3
  #   Wick reject >2.5
  class NoTradeEngine
    Result = Struct.new(:allowed, :score, :reasons, keyword_init: true)

    # Validate context and determine if trade should be allowed
    # @param ctx [OpenStruct] Context from NoTradeContextBuilder
    # @return [Result] Validation result with allowed flag, score, and reasons
    def self.validate(ctx)
      reasons = []
      score = 0
      soft_penalties = 0

      index_key = ctx.index_key&.to_s&.upcase || 'NIFTY'
      is_sensex = index_key.include?('SENSEX')
      is_nifty = index_key == 'NIFTY'

      # --- Trend Weakness (Index-Specific) ---
      # NIFTY: ADX <14 hard reject, 14-18 soft penalty
      # SENSEX: ADX <12 hard reject, 12-16 soft penalty
      adx_hard_threshold = is_nifty ? 14 : (is_sensex ? 12 : 14)
      adx_soft_threshold = is_nifty ? 18 : (is_sensex ? 16 : 18)

      if ctx.adx_5m < adx_hard_threshold
        reasons << "Weak trend: ADX < #{adx_hard_threshold}"
        score += 1
      elsif ctx.adx_5m < adx_soft_threshold
        reasons << "Moderate trend: ADX #{ctx.adx_5m.round(1)} (#{adx_hard_threshold}-#{adx_soft_threshold})"
        soft_penalties += 1
      end

      # DI separation threshold
      # NIFTY: <2 hard reject
      # SENSEX: <1.5 hard reject
      di_threshold = is_nifty ? 2.0 : (is_sensex ? 1.5 : 2.0)
      di_diff = (ctx.plus_di_5m - ctx.minus_di_5m).abs
      if di_diff < di_threshold
        reasons << "DI overlap: no directional strength (diff: #{di_diff.round(2)} < #{di_threshold})"
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

      # VWAP chop detection (index-specific)
      # NIFTY: ±0.08% for 3+ candles
      # SENSEX: ±0.06% for 2+ candles
      if ctx.vwap_chop
        threshold_pct = is_nifty ? 0.08 : (is_sensex ? 0.06 : 0.08)
        min_candles = is_nifty ? 3 : (is_sensex ? 2 : 3)
        reasons << "VWAP chop: price within ±#{threshold_pct}% for #{min_candles}+ candles"
        score += 1
      end

      # --- Volatility Filters (Index-Specific) ---
      # NIFTY: <0.06% hard reject, 0.06-0.1% soft penalty
      # SENSEX: <0.04% hard reject, 0.04-0.08% soft penalty
      range_hard_threshold = is_nifty ? 0.06 : (is_sensex ? 0.04 : 0.06)
      range_soft_threshold = is_nifty ? 0.1 : (is_sensex ? 0.08 : 0.1)

      if ctx.range_10m_pct < range_hard_threshold
        reasons << "Low volatility: 10m range < #{range_hard_threshold}% (#{ctx.range_10m_pct.round(4)})"
        score += 1
      elsif ctx.range_10m_pct < range_soft_threshold
        reasons << "Moderate volatility: 10m range #{ctx.range_10m_pct.round(4)}% (#{range_hard_threshold}-#{range_soft_threshold})"
        soft_penalties += 1
      end

      # ATR downtrend (index-specific bars count already handled in context builder)
      if ctx.atr_downtrend
        reasons << 'ATR decreasing (volatility compression)'
        score += 1
      end

      # --- Option Chain Microstructure (Index-Specific) ---
      # OI trap: Both CE & PE OI rising AND range below threshold
      # NIFTY: CE↑ PE↑ & range <0.08%
      # SENSEX: CE↑ PE↑ & range <0.06%
      oi_trap_range_threshold = is_nifty ? 0.08 : (is_sensex ? 0.06 : 0.08)
      if ctx.ce_oi_up && ctx.pe_oi_up && ctx.range_10m_pct < oi_trap_range_threshold
        reasons << "OI trap: Both CE & PE OI rising & range < #{oi_trap_range_threshold}%"
        score += 1
      elsif ctx.ce_oi_up && ctx.pe_oi_up
        reasons << 'Both CE & PE OI rising (writers controlling)'
        soft_penalties += 1
      end

      # IV thresholds (index-specific)
      # NIFTY: <9 hard reject, 9-11 soft penalty
      # SENSEX: <11 hard reject, 11-13 soft penalty
      iv_hard_threshold = is_nifty ? 9 : (is_sensex ? 11 : 9)
      iv_soft_threshold = is_nifty ? 11 : (is_sensex ? 13 : 11)

      if ctx.iv < iv_hard_threshold
        reasons << "IV too low: #{ctx.iv.round(2)} < #{iv_hard_threshold}"
        score += 1
      elsif ctx.iv < iv_soft_threshold
        reasons << "IV moderate: #{ctx.iv.round(2)} (#{iv_hard_threshold}-#{iv_soft_threshold})"
        soft_penalties += 1
      end

      if ctx.iv_falling
        reasons << 'IV decreasing'
        score += 1
      end

      # Spread thresholds (index-specific)
      # NIFTY: >3 hard reject, >2 soft penalty
      # SENSEX: >5 hard reject, >3 soft penalty
      if ctx.spread_wide
        reasons << 'Wide bid-ask spread (hard threshold)'
        score += 1
      elsif ctx.spread_wide_soft
        reasons << 'Wide bid-ask spread (soft threshold)'
        soft_penalties += 1
      end

      # --- Candle Quality (Index-Specific) ---
      # NIFTY: >2.2 hard reject, 1.8-2.2 soft penalty
      # SENSEX: >2.5 hard reject, 2.0-2.5 soft penalty
      wick_hard_threshold = is_nifty ? 2.2 : (is_sensex ? 2.5 : 2.2)
      wick_soft_threshold = is_nifty ? 1.8 : (is_sensex ? 2.0 : 1.8)

      if ctx.avg_wick_ratio > wick_hard_threshold
        reasons << "High wick ratio: #{ctx.avg_wick_ratio.round(2)} > #{wick_hard_threshold}"
        score += 1
      elsif ctx.avg_wick_ratio > wick_soft_threshold
        reasons << "Moderate wick ratio: #{ctx.avg_wick_ratio.round(2)} (#{wick_soft_threshold}-#{wick_hard_threshold})"
        soft_penalties += 1
      end

      # --- Time Windows ---
      if ctx.time_between.call('09:15', '09:18')
        reasons << 'Avoid first 3 minutes'
        score += 1
      end

      # Lunch-time check: Only block if ADX is weak (< 20) during lunch hours
      # Strong trends (ADX >= 20) can still be traded during lunch
      if ctx.time_between.call('11:20', '13:30') && ctx.adx_5m < 20
        reasons << 'Lunch-time theta zone (weak trend)'
        score += 1
      end

      time_str = ctx.time.is_a?(String) ? ctx.time : ctx.time.strftime('%H:%M')
      if time_str > '15:05'
        reasons << 'Post 3:05 PM - theta crush'
        score += 1
      end

      # Calculate final score: hard rejections count as 1, soft penalties count as 0.5
      # Block trade if score >= 3 (hard rejections) OR (score >= 2 AND soft_penalties >= 2)
      final_score = score + (soft_penalties * 0.5)
      allowed = score < 3 && !(score >= 2 && soft_penalties >= 2)

      Result.new(
        allowed: allowed,
        score: final_score.round(1),
        reasons: reasons
      )
    end
  end
end
