# frozen_string_literal: true

module Smc
  class BiasEngine
    HTF_INTERVAL = '60'
    MTF_INTERVAL = '15'
    LTF_INTERVAL = '5'

    HTF_CANDLES = 60
    MTF_CANDLES = 100
    LTF_CANDLES = 150

    def initialize(instrument)
      @instrument = instrument
    end

    def decision
      htf = context_for(interval: HTF_INTERVAL, max_candles: HTF_CANDLES)
      mtf = context_for(interval: MTF_INTERVAL, max_candles: MTF_CANDLES)
      ltf = context_for(interval: LTF_INTERVAL, max_candles: LTF_CANDLES)

      return :no_trade unless htf_bias_valid?(htf)
      return :no_trade unless mtf_aligns?(htf, mtf)

      decision = ltf_entry(htf, mtf, ltf)
      notify(decision, htf, mtf, ltf) if %i[call put].include?(decision)
      decision
    end

    def details
      htf_series = @instrument.candles(interval: HTF_INTERVAL)
      mtf_series = @instrument.candles(interval: MTF_INTERVAL)
      ltf_series = @instrument.candles(interval: LTF_INTERVAL)

      htf = Smc::Context.new(trim_series(htf_series, max_candles: HTF_CANDLES))
      mtf = Smc::Context.new(trim_series(mtf_series, max_candles: MTF_CANDLES))
      ltf = Smc::Context.new(trim_series(ltf_series, max_candles: LTF_CANDLES))

      avrz = Avrz::Detector.new(ltf_series)

      {
        decision: decision,
        timeframes: {
          htf: { interval: HTF_INTERVAL, context: htf.to_h },
          mtf: { interval: MTF_INTERVAL, context: mtf.to_h },
          ltf: { interval: LTF_INTERVAL, context: ltf.to_h, avrz: avrz.to_h }
        }
      }
    end

    # Analyze SMC/AVRZ data with AI (Ollama or OpenAI)
    # Returns AI analysis of the market structure, liquidity, and trading bias
    def analyze_with_ai(stream: false, &)
      return nil unless ai_enabled?

      details_data = details
      prompt = build_smc_analysis_prompt(details_data)

      model = select_ai_model

      if stream && block_given?
        full_response = +''
        begin
          ai_client.chat_stream(
            messages: [
              { role: 'system', content: smc_ai_system_prompt },
              { role: 'user', content: prompt }
            ],
            model: model,
            temperature: 0.3
          ) do |chunk|
            if chunk.present?
              full_response << chunk
              yield(chunk)
            end
          end
        rescue StandardError => e
          Rails.logger.error("[Smc::BiasEngine] AI stream error: #{e.class} - #{e.message}")
        end
        full_response.presence
      else
        ai_client.chat(
          messages: [
            { role: 'system', content: smc_ai_system_prompt },
            { role: 'user', content: prompt }
          ],
          model: model,
          temperature: 0.3
        )
      end
    rescue StandardError => e
      Rails.logger.error("[Smc::BiasEngine] AI analysis error: #{e.class} - #{e.message}")
      nil
    end

    private

    def context_for(interval:, max_candles:)
      series = @instrument.candles(interval: interval)
      trimmed = trim_series(series, max_candles: max_candles)
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

    def build_smc_analysis_prompt(details_data)
      symbol_name = @instrument.symbol_name || 'UNKNOWN'
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

    def htf_bias_valid?(ctx)
      ctx.pd.discount? || ctx.pd.premium?
    end

    def mtf_aligns?(htf, mtf)
      htf.structure.trend == mtf.structure.trend || mtf.structure.choch?
    end

    def ltf_entry(htf, _mtf, ltf)
      avrz = Avrz::Detector.new(@instrument.candles(interval: LTF_INTERVAL))
      return :no_trade unless avrz.rejection?

      if htf.pd.discount? && ltf.liquidity.sell_side_taken? && ltf.structure.choch?
        :call
      elsif htf.pd.premium? && ltf.liquidity.buy_side_taken? && ltf.structure.choch?
        :put
      else
        :no_trade
      end
    end

    def notify(decision, htf, mtf, ltf)
      signal = Smc::SignalEvent.new(
        instrument: @instrument,
        decision: decision,
        timeframe: '5m',
        price: @instrument.latest_ltp,
        reasons: build_reasons(htf, mtf, ltf)
      )

      Notifications::Telegram::SmcAlert.new(signal).notify!
    rescue StandardError => e
      Rails.logger.error("[Smc::BiasEngine] #{e.class} - #{e.message}")
      nil
    end

    def build_reasons(htf, mtf, ltf)
      reasons = []

      reasons << "HTF in #{htf.pd.discount? ? 'Discount (Demand)' : 'Premium (Supply)'}"
      reasons << '15m CHoCH detected' if mtf.structure.choch?
      reasons << "Liquidity sweep on 5m (#{ltf.liquidity.sweep_direction})"
      reasons << 'AVRZ rejection confirmed'

      reasons
    end
  end
end
