# frozen_string_literal: true

module Smc
  # Background work for tick-throttled SMC: MTF digest, rising-edge, Ollama, Telegram.
  class TickAiDigestJob < ApplicationJob
    queue_as :background

    retry_on StandardError, wait: :polynomially_longer, attempts: 2

    def perform(instrument_id:, ltp:, tick_at: nil)
      instrument = Instrument.find_by(id: instrument_id)
      unless instrument
        Rails.logger.warn("[Smc::TickAiDigestJob] Instrument missing id=#{instrument_id}")
        return
      end

      signals_cfg = AlgoConfig.fetch[:signals] || {}
      return unless signals_cfg[:tick_ai_analysis_enabled] == true
      return unless ai_enabled?
      return if Ai::GenerativeAiMarketGate.skip?(force: false)

      intervals = signals_cfg[:smc_confluence_intervals] || {}
      htf = (intervals[:htf] || intervals['htf'] || BiasEngine::HTF_INTERVAL).to_s
      mtf = (intervals[:mtf] || intervals['mtf'] || BiasEngine::MTF_INTERVAL).to_s
      ltf = (intervals[:ltf] || intervals['ltf'] || BiasEngine::LTF_INTERVAL).to_s
      delay = (signals_cfg[:tick_ai_candle_fetch_delay_seconds] || Scanner::DELAY_BETWEEN_CANDLE_FETCHES).to_f

      digest = Confluence::MtfDigest.build_from_instrument(
        instrument: instrument,
        htf: htf,
        mtf: mtf,
        ltf: ltf,
        sleep_between: delay
      )

      sid = instrument.security_id.to_s
      previous = TickAi::SnapshotStore.read(sid)
      edge = TickAi::EdgeDetector.evaluate(
        digest: digest,
        ltf_interval: ltf,
        previous_snapshot: previous
      )

      TickAi::SnapshotStore.write(sid, edge.current)

      if edge.bootstrap
        Rails.logger.info(
          "[Smc::TickAiDigestJob] Bootstrap snapshot for #{instrument.symbol_name} (no AI)"
        )
        return
      end

      if edge.fired_keys.empty?
        Rails.logger.debug { "[Smc::TickAiDigestJob] No rising edge for #{instrument.symbol_name}" }
        return
      end

      run_ai_and_notify(instrument, signals_cfg, ltp, edge.fired_keys, tick_at)
    rescue StandardError => e
      Rails.logger.error("[Smc::TickAiDigestJob] #{e.class} - #{e.message}")
      Rails.logger.debug { e.backtrace.first(8).join("\n") }
      raise
    end

    private

    def ai_enabled?
      AlgoConfig.fetch.dig(:ai, :enabled) == true &&
        Services::Ai::OllamaClient.instance.enabled?
    rescue StandardError
      false
    end

    def run_ai_and_notify(instrument, signals_cfg, ltp, fired_keys, tick_at)
      decision = infer_decision(fired_keys)
      delay = (signals_cfg[:tick_ai_candle_fetch_delay_seconds] || Scanner::DELAY_BETWEEN_CANDLE_FETCHES).to_f
      engine = BiasEngine.new(instrument, delay_seconds: delay)
      initial_data = engine.details_without_recursion(decision)
      initial_data[:tick_trigger] = {
        ltp: ltp,
        fired_keys: fired_keys,
        tick_at: tick_at || Time.current.iso8601
      }

      if signals_cfg.fetch(:tick_ai_include_index_ta, true)
        initial_data[:index_ta] = build_index_ta(instrument, signals_cfg)
      end

      analyzer = AiAnalyzer.new(instrument, initial_data: initial_data)
      analysis = analyzer.analyze
      return if analysis.blank?

      permission = decision == :no_trade ? :blocked : :scale_ready
      begin
        Trading::AiOutputSanitizer.validate!(permission: permission, output: analysis)
      rescue Trading::AiOutputSanitizer::ViolatingAiOutputError => e
        Rails.logger.warn("[Smc::TickAiDigestJob] AI sanitizer: #{e.message}")
        return
      end

      return unless signals_cfg.fetch(:tick_ai_notify_telegram, true)

      Notifications::Telegram::SmcTickAiAlert.new(
        instrument: instrument,
        fired_keys: fired_keys,
        ltp: ltp,
        analysis_text: analysis
      ).deliver!
    end

    def infer_decision(fired_keys)
      return :call if fired_keys.include?('long_signal')
      return :put if fired_keys.include?('short_signal')

      :no_trade
    end

    def build_index_ta(instrument, signals_cfg)
      idx = instrument.symbol_name.to_s.downcase.to_sym
      ta_timeframes = signals_cfg[:ta_timeframes] || [5, 15, 60]
      ta_days_back = (signals_cfg[:ta_days_back] || 30).to_i
      analyzer = IndexTechnicalAnalyzer.new(idx)
      result = analyzer.call(timeframes: ta_timeframes, days_back: ta_days_back)
      return nil unless result[:success] && analyzer.success?

      analyzer.result
    rescue StandardError => e
      Rails.logger.warn("[Smc::TickAiDigestJob] index TA failed: #{e.class} - #{e.message}")
      nil
    end
  end
end
