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

        # Fetch AI analysis asynchronously (this is the slow part)
        ai_analysis = fetch_ai_analysis(instrument, decision, htf_context, mtf_context, ltf_context)

        # Build signal event
        signal = Smc::SignalEvent.new(
          instrument: instrument,
          decision: decision.to_sym,
          timeframe: '5m',
          price: price,
          reasons: build_reasons(htf_context, mtf_context, ltf_context),
          ai_analysis: ai_analysis
        )

        # Send Telegram notification (with chunking support)
        SmcAlert.new(signal).notify!

        Rails.logger.info("[SendSmcAlertJob] Alert sent for #{instrument.symbol_name} - #{decision}")
      rescue StandardError => e
        Rails.logger.error("[SendSmcAlertJob] Error sending alert: #{e.class} - #{e.message}")
        Rails.logger.debug { e.backtrace.first(10).join("\n") }
        raise
      end

      private

      def fetch_ai_analysis(instrument, decision, htf_context, mtf_context, ltf_context)
        return nil unless ai_enabled?

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

          prompt = build_smc_analysis_prompt(instrument, details_data)
          model = select_ai_model

          Rails.logger.debug { "[SendSmcAlertJob] Fetching AI analysis for #{instrument.symbol_name}..." }

          ai_client.chat(
            messages: [
              { role: 'system', content: smc_ai_system_prompt },
              { role: 'user', content: prompt }
            ],
            model: model,
            temperature: 0.3
          )
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

      def ai_client
        Services::Ai::OpenaiClient.instance
      end

      def select_ai_model
        if ai_client.provider == :ollama
          ai_client.selected_model || ENV['OLLAMA_MODEL'] || 'llama3'
        else
          'gpt-4o'
        end
      end

      def smc_ai_system_prompt
        <<~PROMPT
          You are an expert Smart Money Concepts (SMC) and market structure analyst specializing in Indian index options trading (NIFTY, BANKNIFTY, SENSEX).

          Analyze the provided SMC/AVRZ data and provide:
          1. Market structure assessment (trend, BOS, CHoCH)
          2. Liquidity analysis (sweeps, liquidity grabs)
          3. Premium/Discount zone assessment
          4. Order block identification and significance
          5. Fair Value Gap (FVG) analysis
          6. AVRZ rejection confirmation
          7. Trading bias recommendation (call/put/no_trade) with reasoning
          8. Risk factors and entry considerations

          Provide clear, actionable analysis focused on practical trading decisions.
        PROMPT
      end

      def build_smc_analysis_prompt(instrument, details_data)
        symbol_name = instrument.symbol_name || 'UNKNOWN'
        decision = details_data[:decision]

        <<~PROMPT
          Analyze the following SMC/AVRZ market structure data for #{symbol_name}:

          Trading Decision: #{decision}

          Market Structure Analysis (Multi-Timeframe):

          #{JSON.pretty_generate(details_data[:timeframes])}

          Please provide:
          1. **Market Structure Summary**: Overall trend, structure breaks, and change of character signals
          2. **Liquidity Assessment**: Where liquidity is being taken and potential sweep zones
          3. **Premium/Discount Analysis**: Current market position relative to equilibrium
          4. **Order Block Significance**: Key order blocks and their relevance
          5. **FVG Analysis**: Fair value gaps and their trading implications
          6. **AVRZ Confirmation**: Rejection signals and timing confirmation
          7. **Trading Recommendation**: Validate or challenge the #{decision} decision with reasoning
          8. **Risk Factors**: Key risks and considerations for this setup
          9. **Entry Strategy**: Optimal entry approach if trading signal is valid

          Focus on actionable insights for options trading.
        PROMPT
      end

      def build_reasons(htf_context, mtf_context, ltf_context)
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

        reasons << 'AVRZ rejection confirmed'

        reasons
      end
    end
  end
end
