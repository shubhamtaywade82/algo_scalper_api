# frozen_string_literal: true

module Smc
  class BiasEngine
    HTF_INTERVAL = '60'
    MTF_INTERVAL = '15'
    LTF_INTERVAL = '5'

    HTF_CANDLES = 60
    MTF_CANDLES = 100
    LTF_CANDLES = 150

    def initialize(instrument, delay_seconds: 0.0)
      @instrument = instrument
      @delay_seconds = delay_seconds.to_f
      @cached_decision = nil
      @cached_contexts = nil
      @cached_permission = nil
      @cached_series_by_interval = {}
    end

    def decision
      return @cached_decision if @cached_decision

      htf = context_for(interval: HTF_INTERVAL, max_candles: HTF_CANDLES)
      mtf = context_for(interval: MTF_INTERVAL, max_candles: MTF_CANDLES)
      ltf = context_for(interval: LTF_INTERVAL, max_candles: LTF_CANDLES)

      unless htf_bias_valid?(htf)
        cache_result(decision: :no_trade, contexts: { htf: htf, mtf: mtf, ltf: ltf }, permission: blocked_permission)
        return :no_trade
      end

      unless mtf_aligns?(htf, mtf)
        cache_result(decision: :no_trade, contexts: { htf: htf, mtf: mtf, ltf: ltf }, permission: blocked_permission)
        return :no_trade
      end

      avrz = Avrz::Detector.new(ltf_series)
      permission = Smc::PermissionResolver.call(htf: htf, mtf: mtf, ltf: ltf, avrz: avrz)
      decision = strict_execution_decision(htf, ltf, avrz)

      # Cache decision and contexts to avoid re-computation
      cache_result(decision: decision, contexts: { htf: htf, mtf: mtf, ltf: ltf }, permission: permission)

      # Notify for trading signals OR for no_trade if AI is enabled (to get AI analysis)
      notify(decision, htf, mtf, ltf) if %i[call put].include?(decision) || (decision == :no_trade && ai_enabled?)

      decision
    end

    def permission
      return @cached_permission.permission if @cached_permission

      # Compute decision once to populate caches (and avoid duplicating candle fetches)
      decision
      @cached_permission&.permission || :blocked
    end

    def permission_details
      # Ensure caches are populated
      decision
      p = @cached_permission
      return { permission: :blocked, bias: :neutral, max_lots: 0, execution_mode: :none, reasons: ['Unavailable'] } unless p

      {
        permission: p.permission,
        bias: p.bias,
        max_lots: p.max_lots,
        execution_mode: p.execution_mode,
        entry_signal: p.entry_signal,
        reasons: p.reasons
      }.compact
    end

    def details
      # Use cached decision if available to avoid recursion
      # If not cached, compute it without triggering notify
      cached_decision = @cached_decision
      unless cached_decision
        # Compute decision without notification to avoid recursion
        htf = context_for(interval: HTF_INTERVAL, max_candles: HTF_CANDLES)
        mtf = context_for(interval: MTF_INTERVAL, max_candles: MTF_CANDLES)
        ltf = context_for(interval: LTF_INTERVAL, max_candles: LTF_CANDLES)

        if htf_bias_valid?(htf) && mtf_aligns?(htf, mtf)
          avrz = Avrz::Detector.new(ltf_series)
          @cached_permission = Smc::PermissionResolver.call(htf: htf, mtf: mtf, ltf: ltf, avrz: avrz)
          cached_decision = strict_execution_decision(htf, ltf, avrz)
        else
          @cached_permission = blocked_permission
          cached_decision = :no_trade
        end
      end

      details_without_recursion(cached_decision)
    end

    def details_without_recursion(decision_value = nil)
      # Use provided decision or cached decision to avoid recursion
      decision_value ||= @cached_decision || :no_trade

      # Add delays between candle fetches to avoid rate limits
      htf_series = @instrument.candles(interval: HTF_INTERVAL)
      sleep(@delay_seconds) if @delay_seconds.positive?

      mtf_series = @instrument.candles(interval: MTF_INTERVAL)
      sleep(@delay_seconds) if @delay_seconds.positive?

      ltf_series = @instrument.candles(interval: LTF_INTERVAL)

      htf = Smc::Context.new(trim_series(htf_series, max_candles: HTF_CANDLES))
      mtf = Smc::Context.new(trim_series(mtf_series, max_candles: MTF_CANDLES))
      ltf = Smc::Context.new(trim_series(ltf_series, max_candles: LTF_CANDLES))

      avrz = Avrz::Detector.new(ltf_series)
      permission = Smc::PermissionResolver.call(htf: htf, mtf: mtf, ltf: ltf, avrz: avrz)

      {
        decision: decision_value,
        permission: {
          level: permission.permission,
          bias: permission.bias,
          max_lots: permission.max_lots,
          execution_mode: permission.execution_mode,
          entry_signal: permission.entry_signal,
          reasons: permission.reasons
        }.compact,
        timeframes: {
          htf: { interval: HTF_INTERVAL, context: htf.to_h },
          mtf: { interval: MTF_INTERVAL, context: mtf.to_h },
          ltf: { interval: LTF_INTERVAL, context: ltf.to_h, avrz: avrz.to_h }
        }
      }
    end

    # Analyze SMC/AVRZ data with AI (Ollama or OpenAI)
    # Returns AI analysis of the market structure, liquidity, and trading bias
    # Uses new AiAnalyzer with chat completion, history, and tool calling
    def analyze_with_ai(stream: false, &)
      return nil unless ai_enabled?

      details_data = details

      analyzer = Smc::AiAnalyzer.new(@instrument, initial_data: details_data)
      analyzer.analyze(stream: stream, &)
    rescue StandardError => e
      Rails.logger.error("[Smc::BiasEngine] AI analysis error: #{e.class} - #{e.message}")
      nil
    end

    def ai_enabled?
      AlgoConfig.fetch.dig(:ai, :enabled) == true &&
        Services::Ai::OpenaiClient.instance.enabled?
    rescue StandardError
      false
    end

    # Analyze with AI for a specific decision (avoids recursion)
    def analyze_with_ai_for_decision(decision_value)
      return nil unless ai_enabled?

      # Use details_without_recursion to avoid calling decision again
      details_data = details_without_recursion(decision_value)

      analyzer = Smc::AiAnalyzer.new(@instrument, initial_data: details_data)
      analyzer.analyze
    rescue StandardError => e
      Rails.logger.error("[Smc::BiasEngine] AI analysis error: #{e.class} - #{e.message}")
      nil
    end

    private

    def context_for(interval:, max_candles:)
      # Add delay before fetching candles to avoid rate limits
      sleep(@delay_seconds) if @delay_seconds.positive?

      series = @instrument.candles(interval: interval)
      trimmed = trim_series(series, max_candles: max_candles)
      @cached_series_by_interval[interval.to_s] = trimmed
      Smc::Context.new(trimmed)
    end

    def trim_series(series, max_candles:)
      return series if series.nil?
      return series unless series.respond_to?(:candles)

      candles = series.candles.last(max_candles)
      return series if candles.size == series.candles.size

      CandleSeries.new(symbol: series.symbol, interval: series.interval).tap do |s|
        candles.each { |c| s.add_candle(c) }
      end
    rescue StandardError => e
      Rails.logger.error("[Smc::BiasEngine] #{e.class} - #{e.message}")
      series
    end


    def htf_bias_valid?(ctx)
      ctx.pd.discount? || ctx.pd.premium?
    end

    def mtf_aligns?(htf, mtf)
      htf.structure.trend == mtf.structure.trend || mtf.structure.choch?
    end

    def ltf_series
      @cached_series_by_interval[LTF_INTERVAL] || @cached_series_by_interval[LTF_INTERVAL.to_s]
    end

    def strict_execution_decision(htf, ltf, avrz)
      return :no_trade unless avrz&.rejection?

      if htf.pd.discount? && ltf.liquidity.sell_side_taken? && ltf.structure.choch?
        :call
      elsif htf.pd.premium? && ltf.liquidity.buy_side_taken? && ltf.structure.choch?
        :put
      else
        :no_trade
      end
    end

    def cache_result(decision:, contexts:, permission:)
      @cached_decision = decision
      @cached_contexts = contexts
      @cached_permission = permission
    end

    def blocked_permission
      Smc::PermissionResolver::Result.new(
        permission: :blocked,
        bias: :neutral,
        max_lots: 0,
        execution_mode: :none,
        reasons: ['Blocked by HTF/MTF'],
        entry_signal: nil
      )
    end

    def notify(decision, htf, mtf, ltf)
      # Enqueue background job for async AI analysis and Telegram notification
      # This prevents blocking the scanner rake task while AI fetches response
      Notifications::Telegram::SendSmcAlertJob.perform_later(
        instrument_id: @instrument.id,
        decision: decision.to_s,
        htf_context: htf.to_h,
        mtf_context: mtf.to_h,
        ltf_context: ltf.to_h,
        price: current_price
      )

      Rails.logger.info("[Smc::BiasEngine] Enqueued alert job for #{@instrument.symbol_name} - #{decision}")
    rescue StandardError => e
      Rails.logger.error("[Smc::BiasEngine] Failed to enqueue alert job: #{e.class} - #{e.message}")
    end

    def build_reasons(htf, mtf, ltf)
      reasons = []

      reasons << "HTF in #{htf.pd.discount? ? 'Discount (Demand)' : 'Premium (Supply)'}"
      reasons << '15m CHoCH detected' if mtf.structure.choch?
      reasons << "Liquidity sweep on 5m (#{ltf.liquidity.sweep_direction})"
      reasons << 'AVRZ rejection confirmed'

      reasons
    end

    def current_price
      @instrument.ltp&.to_f || @instrument.latest_ltp&.to_f || 0.0
    end
  end
end
