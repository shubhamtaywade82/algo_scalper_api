# frozen_string_literal: true

module Smc
  # Tactical overlay on top of PermissionResolver tiers: LTF zone, liquidity, and
  # swing trend. Does not place orders or replace Smc::SmcPermissionResolver.
  class Navigator
    EntryResult = Struct.new(:allow, :reason, :confidence, :details) do
      def allow?
        allow
      end
    end

    ExitResult = Struct.new(:suggest_exit, :reason, :confidence, :details) do
      def suggest_exit?
        suggest_exit
      end
    end

    MIN_CANDLES = 8

    class << self
      # @param price [Float, nil] Underlying reference; defaults to last LTF close
      # @param direction [Symbol] :bullish / :bearish (or :call / :put)
      # @param instrument [Instrument] Index instrument (same as EntryGuard pipeline)
      # @param smc_context [Smc::Context, nil] Optional pre-built context
      def evaluate_entry(price:, direction:, instrument:, smc_context: nil)
        return fail_open_entry(:missing_instrument) unless instrument

        series = instrument.candle_series(interval: Smc::BiasEngine::LTF_INTERVAL)
        return fail_open_entry(:insufficient_smc_data) unless series&.candles&.size.to_i >= MIN_CANDLES

        ctx = smc_context || Smc::Context.new(series)
        px = entry_reference_price(price, series)
        return fail_open_entry(:insufficient_smc_data) if px.nil? || px.to_f <= 0

        dir = normalize_direction(direction)
        return veto_entry(:neutral_direction, 0.2) if dir == :neutral

        trend = ctx.trend
        liq = ctx.liquidity.to_h
        pd = ctx.pd.to_h
        phase = ctx.phase

        details = {
          trend: trend,
          phase: phase,
          liquidity: liq,
          premium_discount: pd,
          reference_price: px.to_f
        }

        return veto_entry(:trend_mismatch, 0.22, details) if opposite_trend?(dir, trend)

        confidence = entry_confidence(dir, trend, liq, pd, phase)
        EntryResult.new(allow: true, reason: :ok, confidence: confidence, details: details)
      rescue StandardError => e
        Rails.logger.error("[Smc::Navigator] #{e.class} - #{e.message}")
        fail_open_entry(:error)
      end

      # @param tracker [PositionTracker]
      # @param ltp [Numeric] Option LTP (logged only; structure uses index series)
      # @param instrument [Instrument] Index instrument
      def evaluate_exit(tracker:, ltp:, instrument:)
        return soft_exit_false(:missing_tracker) unless tracker
        return soft_exit_false(:missing_instrument) unless instrument

        ctx = build_context(instrument)
        return soft_exit_false(:insufficient_smc_data) unless ctx

        long_side = position_long_side(tracker)
        return soft_exit_false(:unknown_option_side) unless long_side

        trend = ctx.trend
        liq = ctx.liquidity.to_h
        details = { trend: trend, liquidity: liq, option_side: long_side, ltp: ltp.to_f }

        suggest, reason, confidence = exit_signal(long_side, trend, liq)
        ExitResult.new(suggest_exit: suggest, reason: reason, confidence: confidence, details: details)
      rescue StandardError => e
        Rails.logger.error("[Smc::Navigator] #{e.class} - #{e.message}")
        soft_exit_false(:error)
      end

      def log_exit_advisory(tracker:, ltp:, instrument:)
        cfg = AlgoConfig.fetch[:signals] || {}
        return unless cfg[:smc_navigator_exit_advisory] == true

        result = evaluate_exit(tracker: tracker, ltp: ltp, instrument: instrument)
        return unless result.suggest_exit?

        Observability::StructuredLog.info(
          event: 'smc_exit_advisory',
          payload: {
            service: 'Smc::Navigator',
            position_id: tracker.id,
            symbol: tracker.symbol,
            reason: result.reason,
            confidence: result.confidence,
            details: result.details
          }
        )
      end

      private

      def build_context(instrument)
        series = instrument.candle_series(interval: Smc::BiasEngine::LTF_INTERVAL)
        return nil unless series&.candles&.size.to_i >= MIN_CANDLES

        Smc::Context.new(series)
      end

      def entry_reference_price(price, series)
        p = price.presence&.to_f
        return p if p&.positive?

        series.candles.last&.close&.to_f
      end

      def normalize_direction(direction)
        d = direction.to_s.downcase.to_sym
        return :bullish if %i[bullish call long_ce].include?(d)
        return :bearish if %i[bearish put long_pe].include?(d)

        :neutral
      end

      def opposite_trend?(direction, trend)
        return false if trend == :range

        (direction == :bullish && trend == :bearish) || (direction == :bearish && trend == :bullish)
      end

      def entry_confidence(direction, trend, liq, pd, phase)
        score = 0.45

        score += trend_aligned_bonus(direction, trend)
        score += zone_bonus(direction, pd)
        score += liquidity_bonus(direction, liq)
        score -= 0.12 if phase == :trap_detected

        score.clamp(0.0, 1.0)
      end

      def trend_aligned_bonus(direction, trend)
        return 0.22 if (direction == :bullish && trend == :bullish) || (direction == :bearish && trend == :bearish)
        return 0.08 if trend == :range

        0.0
      end

      def zone_bonus(direction, pd)
        if direction == :bullish
          return 0.18 if pd[:discount]
          return -0.08 if pd[:premium]
        elsif direction == :bearish
          return 0.18 if pd[:premium]
          return -0.08 if pd[:discount]
        end
        0.0
      end

      def liquidity_bonus(direction, liq)
        if direction == :bullish && liq[:sell_side_taken]
          0.12
        elsif direction == :bearish && liq[:buy_side_taken]
          0.12
        else
          0.0
        end
      end

      def veto_entry(reason, confidence, details = {})
        EntryResult.new(allow: false, reason: reason, confidence: confidence, details: details)
      end

      def fail_open_entry(reason)
        EntryResult.new(allow: true, reason: reason, confidence: 1.0, details: {})
      end

      def position_long_side(tracker)
        sym = tracker.symbol.to_s.upcase
        return :call if sym.include?('CE')
        return :put if sym.include?('PE')

        nil
      end

      def exit_signal(long_side, trend, liq)
        if long_side == :call
          return [true, :structure_bearish, 0.72] if trend == :bearish
          return [true, :opposite_liquidity_sweep, 0.65] if liq[:buy_side_taken]

          return [false, :aligned, 0.2]
        elsif long_side == :put
          return [true, :structure_bullish, 0.72] if trend == :bullish
          return [true, :opposite_liquidity_sweep, 0.65] if liq[:sell_side_taken]

          return [false, :aligned, 0.2]
        end

        [false, :unknown, 0.0]
      end

      def soft_exit_false(reason)
        ExitResult.new(suggest_exit: false, reason: reason, confidence: 0.0, details: {})
      end
    end
  end
end
