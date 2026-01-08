# frozen_string_literal: true

module Notifications
  module Telegram
    class SendSmcAlertJob < ApplicationJob
      queue_as :background

      # Retry with exponential backoff for transient failures
      retry_on StandardError, wait: :exponentially_longer, attempts: 3

      def perform(instrument_id:, decision:, htf_context:, mtf_context:, ltf_context:, price:)
        instrument = Instrument.find_by(id: instrument_id)
        unless instrument
          Rails.logger.warn("[SendSmcAlertJob] Instrument not found: #{instrument_id}")
          return
        end

        Rails.logger.info("[SendSmcAlertJob] Processing alert for #{instrument.symbol_name} - #{decision}")

        # Fetch fresh AVRZ data once (this is the only real-time timing input we need)
        ltf_series = instrument.candles(interval: Smc::BiasEngine::LTF_INTERVAL)
        avrz = Avrz::Detector.new(ltf_series)

        # Fetch AI analysis asynchronously (this is the slow part)
        ai_analysis = fetch_ai_analysis(instrument, decision, htf_context, mtf_context, ltf_context, avrz: avrz)

        if ai_analysis.present?
          Rails.logger.info("[SendSmcAlertJob] AI analysis received (#{ai_analysis.length} chars) for #{instrument.symbol_name}")
        else
          Rails.logger.warn("[SendSmcAlertJob] AI analysis is empty or nil for #{instrument.symbol_name}")
        end

        # Build signal event
        signal = Smc::SignalEvent.new(
          instrument: instrument,
          decision: decision.to_sym,
          timeframe: '5m',
          price: price,
          reasons: build_reasons(htf_context, mtf_context, ltf_context, avrz: avrz),
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

      def fetch_ai_analysis(instrument, decision, htf_context, mtf_context, ltf_context, avrz:)
        return nil unless ai_enabled?

        begin
          # Build details for AI prompt using serialized context data
          details_data = {
            decision: decision.to_sym,
            permission: Smc::PermissionResolver.call(
              htf: htf_context,
              mtf: mtf_context,
              ltf: ltf_context,
              avrz: avrz
            )&.permission,
            timeframes: {
              htf: { interval: Smc::BiasEngine::HTF_INTERVAL, context: htf_context },
              mtf: { interval: Smc::BiasEngine::MTF_INTERVAL, context: mtf_context },
              ltf: { interval: Smc::BiasEngine::LTF_INTERVAL, context: ltf_context, avrz: avrz.to_h }
            }
          }

          Rails.logger.debug { "[SendSmcAlertJob] Fetching AI analysis for #{instrument.symbol_name}..." }

          # Use new AiAnalyzer with chat completion, history, and tool calling
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
          Services::Ai::OpenaiClient.instance.enabled?
      rescue StandardError
        false
      end

      def build_reasons(htf_context, mtf_context, ltf_context, avrz:)
        reasons = []

        permission = Smc::PermissionResolver.call(htf: htf_context, mtf: mtf_context, ltf: ltf_context, avrz: avrz)
        if permission
          reasons << "Permission: #{permission.permission} (max_lots=#{permission.max_lots}, mode=#{permission.execution_mode})"
        end

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

        # Check for CHoCH in MTF swing structure
        if mtf_context[:swing_structure] && mtf_context[:swing_structure][:choch]
          reasons << '15m CHoCH detected'
        elsif mtf_context[:structure] && mtf_context[:structure][:choch]
          reasons << '15m CHoCH detected'
        end

        # Check for liquidity sweep in LTF
        if ltf_context[:liquidity]
          liq_data = ltf_context[:liquidity]
          if liq_data[:sell_side_taken]
            reasons << 'Liquidity sweep on 5m (sell-side)'
          elsif liq_data[:buy_side_taken]
            reasons << 'Liquidity sweep on 5m (buy-side)'
          end
        end

        reasons << (avrz.rejection? ? 'AVRZ rejection confirmed' : 'AVRZ not confirmed (timing missing)')

        reasons
      end
    end
  end
end
