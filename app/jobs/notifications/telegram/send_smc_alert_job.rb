# frozen_string_literal: true

module Notifications
  module Telegram
    class SendSmcAlertJob < ApplicationJob
      queue_as :background

      # Retry with exponential backoff for transient failures
      # Use proc for exponential backoff: 2^attempt seconds
      retry_on StandardError, wait: ->(executions) { 2**executions }, attempts: 3

      def perform(instrument_id:, decision:, contexts:, price:)
        instrument = Instrument.find_by(id: instrument_id)
        unless instrument
          Rails.logger.warn("[SendSmcAlertJob] Instrument not found: #{instrument_id}")
          return
        end

        Rails.logger.info("[SendSmcAlertJob] Processing alert for #{instrument.symbol_name} - #{decision}")

        # Fetch AI analysis asynchronously (this is the slow part)
        # Skip AI analysis for 'no_trade' decisions to avoid validation errors
        ai_analysis = if decision.to_s == 'no_trade'
                        nil
                      else
                        fetch_ai_analysis(instrument, decision, contexts)
                      end

        # Enforce permission-based AI output constraints (no discretionary overrides)
        # Only validate if we have AI analysis and it's not a no_trade decision
        if ai_analysis.present?
          permission = decision.to_s == 'no_trade' ? :blocked : :scale_ready
          begin
            Trading::AiOutputSanitizer.validate!(permission: permission, output: ai_analysis)
          rescue Trading::AiOutputSanitizer::ViolatingAiOutputError => e
            Rails.logger.warn("[SendSmcAlertJob] AI output validation failed: #{e.message}. Skipping AI analysis.")
            ai_analysis = nil # Remove invalid AI analysis
          end
        end

        log_ai_analysis_status(instrument: instrument, ai_analysis: ai_analysis, decision: decision)

        # Build signal event
        signal = Smc::SignalEvent.new(
          instrument: instrument,
          decision: decision.to_sym,
          timeframe: '5m',
          price: price,
          reasons: build_reasons(contexts, decision: decision),
          ai_analysis: ai_analysis
        )

        Rails.logger.debug { "[SendSmcAlertJob] Signal created - decision: #{signal.decision}, ai_analysis present: #{signal.ai_analysis.present?}, valid: #{signal.valid?}" }

        # Send Telegram notification (with chunking support)
        SmcAlert.new(signal).notify!

        Rails.logger.info("[SendSmcAlertJob] Alert sent for #{instrument.symbol_name} - #{decision}")
      rescue StandardError => e
        Rails.logger.error("[SendSmcAlertJob] Error sending alert: #{e.class} - #{e.message}")
        Rails.logger.debug { e.backtrace.first(10).join("\n") }
        raise
      end

      private

      def fetch_ai_analysis(instrument, decision, contexts)
        return nil unless ai_enabled?

        htf_context = contexts[:htf] || {}
        mtf_context = contexts[:mtf] || {}
        ltf_context = contexts[:ltf] || {}

        begin
          # Fetch fresh AVRZ data (this is the only real-time data we need)
          ltf_series = instrument.candles(interval: Smc::BiasEngine::LTF_INTERVAL)
          avrz = Avrz::Detector.new(ltf_series)

          # Build details for AI prompt using serialized context data
          details_data = {
            decision: decision.to_sym,
            timeframes: {
              htf: { interval: Smc::BiasEngine::HTF_INTERVAL, context: htf_context },
              mtf: { interval: Smc::BiasEngine::MTF_INTERVAL, context: mtf_context },
              ltf: { interval: Smc::BiasEngine::LTF_INTERVAL, context: ltf_context, avrz: avrz.to_h }
            }
          }

          # Enrich with outputs from LTF engines (Displacement, Volume, Zone, Navigator).
          # These run in the background job so the scanner thread stays fast.
          details_data[:ltf_engines] = build_ltf_enrichment(instrument, ltf_series, decision)

          Rails.logger.debug { "[SendSmcAlertJob] Fetching AI analysis for #{instrument.symbol_name}..." }

          # Use AiAnalyzer with pre-fetched data and single-pass analysis
          analyzer = Smc::AiAnalyzer.new(instrument, initial_data: details_data)
          result = analyzer.analyze

          if result.present?
            Rails.logger.info("[SendSmcAlertJob] AI analysis generated successfully (#{result.length} chars) for #{instrument.symbol_name}")
          else
            Rails.logger.warn("[SendSmcAlertJob] AI analyzer returned empty result for #{instrument.symbol_name}")
          end

          result
        rescue StandardError => e
          Rails.logger.warn("[SendSmcAlertJob] Failed to get AI analysis: #{e.class} - #{e.message}")
          nil
        end
      end

      def ai_enabled?
        AlgoConfig.fetch.dig(:ai, :enabled) == true &&
          Services::Ai::OllamaClient.instance.enabled?
      rescue StandardError
        false
      end

      def build_reasons(contexts, decision:)
        context_decision = contexts[:decision]
        if context_decision.present? && context_decision.to_s.casecmp(decision.to_s) != 0
          Rails.logger.warn(
            "[SendSmcAlertJob] decision/context mismatch: job_decision=#{decision.inspect} " \
            "contexts[:decision]=#{context_decision.inspect}"
          )
        end

        htf_context = contexts[:htf] || {}
        mtf_context = contexts[:mtf] || {}
        ltf_context = contexts[:ltf] || {}

        reasons = []

        # Use serialized context data to build reasons
        # Context keys: premium_discount, swing_structure (or structure), liquidity
        if htf_context[:premium_discount]
          pd_data = htf_context[:premium_discount]
          if pd_data[:discount]
            reasons << 'HTF in Discount (Demand)'
          elsif pd_data[:premium]
            reasons << 'HTF in Premium (Supply)'
          end
        end

        append_liquidity_reasons(reasons, htf_context[:liquidity], label: 'HTF')
        append_liquidity_reasons(reasons, ltf_context[:liquidity], label: '5m')

        # Check for CHoCH in MTF swing structure
        if (mtf_context[:swing_structure] && mtf_context[:swing_structure][:choch]) ||
           (mtf_context[:structure] && mtf_context[:structure][:choch])
          reasons << '15m CHoCH detected'
        end

        # MTF / LTF trend snapshot (helps explain no_trade when internal vs swing diverge)
        append_trend_mismatch_hint(reasons, mtf_context, ltf_context)

        # AVRZ is only evaluated for actionable signals; do not claim it on no_trade scans.
        reasons << 'AVRZ rejection confirmed' if %w[call put].include?(decision.to_s)

        reasons
      end

      def append_liquidity_reasons(reasons, liq_data, label:)
        return unless liq_data

        if liq_data[:sell_side_taken]
          reasons << "Liquidity sweep on #{label} (sell-side)"
        elsif liq_data[:buy_side_taken]
          reasons << "Liquidity sweep on #{label} (buy-side)"
        end
      end

      def append_trend_mismatch_hint(reasons, mtf_context, ltf_context)
        mtf_swing = mtf_context[:swing_structure] || mtf_context[:structure]
        mtf_int = mtf_context[:internal_structure]
        if mtf_swing && mtf_int && mtf_swing[:trend] && mtf_int[:trend] &&
           mtf_swing[:trend] != mtf_int[:trend]
          reasons << "15m internal trend #{mtf_int[:trend]} vs swing trend #{mtf_swing[:trend]}"
        end

        ltf_swing = ltf_context[:swing_structure] || ltf_context[:structure]
        ltf_int = ltf_context[:internal_structure]
        if ltf_swing && ltf_int && ltf_swing[:trend] && ltf_int[:trend] &&
           ltf_swing[:trend] != ltf_int[:trend]
          reasons << "5m internal trend #{ltf_int[:trend]} vs swing trend #{ltf_swing[:trend]}"
        end
      end

      def log_ai_analysis_status(instrument:, ai_analysis:, decision:)
        if ai_analysis.present?
          Rails.logger.info(
            "[SendSmcAlertJob] AI analysis received (#{ai_analysis.length} chars) for #{instrument.symbol_name}"
          )
        elsif decision.to_s == 'no_trade'
          Rails.logger.debug { "[SendSmcAlertJob] No AI run for no_trade (#{instrument.symbol_name})" }
        else
          Rails.logger.warn("[SendSmcAlertJob] AI analysis is empty or nil for #{instrument.symbol_name}")
        end
      end

      # Runs DisplacementEngine, VolumeEngine, ZoneEngine, and Navigator on the current LTF series.
      # Returns a hash that is merged into the AI prompt via initial_data[:ltf_engines].
      def build_ltf_enrichment(instrument, ltf_series, decision)
        price = instrument.ltp&.to_f || instrument.latest_ltp&.to_f
        direction = decision.to_sym == :call ? :bullish : :bearish

        displacement = Smc::DisplacementEngine.new(ltf_series).call
        volume = Smc::VolumeEngine.new(ltf_series).call
        zone = Smc::ZoneEngine.new(ltf_series).call(price: price)

        navigator = if price&.positive?
                      Smc::Navigator.evaluate_entry(
                        price: price,
                        direction: direction,
                        instrument: instrument
                      )
                    end

        atr = displacement.atr.to_f
        body = displacement.body.to_f

        {
          displacement: {
            bullish: displacement.bullish,
            bearish: displacement.bearish,
            body: body.round(2),
            atr: atr.round(2),
            body_atr_ratio: atr.positive? ? (body / atr).round(3) : 0.0
          },
          volume: {
            spike: volume.spike,
            ratio: volume.ratio.round(3),
            current: volume.current.to_i,
            avg: volume.avg.round(2)
          },
          zone: {
            location: zone[:location]&.to_s,
            equilibrium: zone[:equilibrium]&.round(2)
          },
          navigator: navigator ? {
            allow: navigator.allow,
            reason: navigator.reason.to_s,
            confidence: navigator.confidence.round(3)
          } : nil
        }
      rescue StandardError => e
        Rails.logger.warn("[SendSmcAlertJob] LTF enrichment failed: #{e.class} - #{e.message}")
        {}
      end
    end
  end
end
