# frozen_string_literal: true

module Live
  # Evaluates underlying index state to inform trailing stop behaviour.
  # Included into Live::UnifiedExitChecker's singleton class.
  #
  # Returns { action: :exit | :tighten | :hold, multiplier: Float, reason: String | nil }
  # Only evaluates when trailing is already armed (position is profitable enough).
  #
  # :exit     — BOS broken against position, or dual weakness (trend + ATR)
  # :tighten  — single weakness signal; caller compresses allowed_dd by multiplier
  # :hold     — underlying healthy or data unavailable; trailing unchanged
  module UnderlyingContextEvaluator
    def evaluate_underlying_context(tracker, snapshot)
      cfg = underlying_context_cfg
      return hold_result unless cfg[:enabled]
      return hold_result unless trailing_armed?(tracker, snapshot, exit_config)

      pos_data = Positions::ActiveCache.instance.get_by_tracker_id(tracker.id)
      underlying_pd = build_underlying_position_data(tracker, pos_data)
      state = Live::UnderlyingMonitor.evaluate(underlying_pd)
      return hold_result unless state

      direction = resolve_position_direction(tracker, pos_data)

      if bos_broken_against?(state, direction)
        return exit_result("UNDERLYING_STRUCTURE_BREAK (BOS #{state.bos_direction}, " \
                           "tracker=#{tracker.order_no})")
      end

      weak   = trend_weak?(state, cfg)
      collap = atr_collapsing?(state, cfg)

      if weak && collap
        return exit_result("UNDERLYING_DUAL_WEAKNESS (trend_score=#{state.trend_score&.round(1)}, " \
                           "atr_ratio=#{state.atr_ratio&.round(3)}, tracker=#{tracker.order_no})")
      end

      if weak || collap
        signal = weak ? "trend_score=#{state.trend_score&.round(1)}" : "atr_ratio=#{state.atr_ratio&.round(3)}"
        return tighten_result("UNDERLYING_WEAKENING (#{signal}, tracker=#{tracker.order_no})",
                              multiplier: cfg[:tightening_multiplier].to_f)
      end

      hold_result
    rescue StandardError => e
      Rails.logger.error("[UnderlyingContextEvaluator] evaluate failed: #{e.class} - #{e.message}")
      hold_result
    end

    private

    # Build the position_data OpenStruct that UnderlyingMonitor.evaluate expects.
    # Reads underlying_segment and underlying_security_id from ActiveCache pos_data
    # (already populated by Positions::MetadataResolver at entry time).
    def build_underlying_position_data(tracker, pos_data)
      index_key = tracker.index_key

      OpenStruct.new(
        tracker_id: tracker.id,
        index_key: index_key,
        underlying_symbol: index_key, # fallback in UnderlyingMonitor#determine_index_cfg
        underlying_segment: pos_data&.underlying_segment,
        underlying_security_id: pos_data&.underlying_security_id,
        position_direction: resolve_position_direction(tracker, pos_data),
        underlying_ltp: nil # UnderlyingMonitor fetches via TickQuery
      )
    end

    # Normalise raw direction value to :bullish / :bearish.
    # UnderlyingMonitor#structure_state only handles these two symbols.
    # Safe default: :bullish — unknown direction → false negative, never false positive.
    def resolve_position_direction(tracker, pos_data)
      raw = pos_data&.position_direction.presence ||
            tracker.direction.presence

      case raw.to_s.downcase
      when 'long_pe', 'bearish', 'put' then :bearish
      when 'long_ce', 'bullish', 'call' then :bullish
      else :bullish
      end
    end

    def bos_broken_against?(state, direction)
      return false unless state.bos_state == :broken

      (direction == :bullish && state.bos_direction == :bearish) ||
        (direction == :bearish && state.bos_direction == :bullish)
    end

    def trend_weak?(state, cfg)
      return false unless state.trend_score

      state.trend_score.to_f < cfg[:trend_score_threshold].to_f
    end

    def atr_collapsing?(state, cfg)
      state.atr_trend == :falling &&
        state.atr_ratio &&
        state.atr_ratio.to_f < cfg[:atr_ratio_threshold].to_f
    end

    def underlying_context_cfg
      cfg = AlgoConfig.fetch.dig(:risk, :underlying_context_exit) || {}
      {
        enabled: cfg.fetch(:enabled, true),
        trend_score_threshold: cfg.fetch(:trend_score_threshold, 15).to_f,
        atr_ratio_threshold: cfg.fetch(:atr_ratio_threshold, 0.65).to_f,
        tightening_multiplier: cfg.fetch(:tightening_multiplier, 0.5).to_f
      }
    rescue StandardError
      { enabled: false, trend_score_threshold: 15.0, atr_ratio_threshold: 0.65,
        tightening_multiplier: 0.5 }
    end

    def hold_result
      { action: :hold, multiplier: 1.0, reason: nil }
    end

    def tighten_result(reason, multiplier:)
      { action: :tighten, multiplier: multiplier.to_f, reason: reason }
    end

    def exit_result(reason)
      { action: :exit, multiplier: 1.0, reason: reason }
    end

    # Provided here so the module is self-contained when included in a standalone host
    # (e.g. spec host classes). UnifiedExitChecker defines its own version which takes
    # precedence when the module is included into that class's singleton.
    def trailing_armed?(tracker, snapshot, config)
      trailing_cfg = config[:trailing] || {}
      return false unless trailing_cfg[:enabled]

      activation = trailing_cfg[:activation_profit].to_f
      return false unless activation.positive?

      entry_value = tracker.entry_price.to_f * tracker.quantity.to_i
      return false unless entry_value.positive?

      hwm = snapshot[:hwm_pnl].to_f
      return false unless hwm.positive?

      peak_profit_pct = hwm / entry_value
      peak_profit_pct >= activation
    end
  end
end
