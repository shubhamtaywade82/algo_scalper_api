# frozen_string_literal: true

module Smc
  class AiBiasValidator < ApplicationService
    RESPONSE_KEYS = %w[
      market_bias
      market_regime
      directional_allowance
      decision_alignment
      decision_valid
      confidence
      suggested_duration
      explanation
    ].freeze

    MARKET_BIASES = %w[bullish bearish range].freeze
    MARKET_REGIMES = %w[trending rangebound].freeze
    DIRECTIONAL_ALLOWANCES = %w[CE_ONLY PE_ONLY NEITHER].freeze
    DECISION_ALIGNMENTS = %w[ALIGNED CONFLICT NO_TRADE_OK].freeze
    DURATION_OPTIONS = %w[1m 5m 15m 30m 60m].freeze

    DEFAULT_OLLAMA_MODEL = 'llama3.2:3b'
    DEFAULT_OPENAI_MODEL = 'gpt-4o'

    VALIDATORS = {
      'market_bias' => ->(value) { MARKET_BIASES.include?(value) },
      'market_regime' => ->(value) { MARKET_REGIMES.include?(value) },
      'directional_allowance' => ->(value) { DIRECTIONAL_ALLOWANCES.include?(value) },
      'decision_alignment' => ->(value) { DECISION_ALIGNMENTS.include?(value) },
      'decision_valid' => ->(value) { value == true || value == false },
      'confidence' => ->(value) { value.is_a?(Numeric) && value >= 0 && value <= 100 },
      'suggested_duration' => ->(value) { DURATION_OPTIONS.include?(value) },
      'explanation' => ->(value) { value.is_a?(String) }
    }.freeze

    def initialize(initial_data:)
      @initial_data = initial_data
      @client = Services::Ai::OpenaiClient.instance
      @model = select_model
    end

    def call
      return nil unless enabled?

      build_response
    rescue StandardError => e
      log_error("Error: #{e.class} - #{e.message}")
      nil
    end

    private

    def enabled?
      AlgoConfig.fetch.dig(:ai, :enabled) == true && @client.enabled?
    rescue StandardError
      false
    end

    def build_response
      payload = parse_response(request_analysis)
      payload ? JSON.generate(payload) : nil
    end

    def request_analysis
      @client.chat(
        messages: prompt_messages,
        model: @model,
        temperature: 0.1
      )
    end

    def prompt_messages
      [
        { role: 'system', content: system_prompt },
        { role: 'user', content: user_prompt }
      ]
    end

    def select_model
      return ollama_model if @client.provider == :ollama

      DEFAULT_OPENAI_MODEL
    end

    def ollama_model
      @client.selected_model || ENV['OLLAMA_MODEL'] || DEFAULT_OLLAMA_MODEL
    end

    def parse_response(response)
      payload = parse_json(response_content(response))
      return nil unless payload
      return payload if valid_schema?(payload)

      log_warn('AI response failed schema validation')
      nil
    end

    def parse_json(content)
      return nil if content.empty?

      JSON.parse(content)
    rescue JSON::ParserError => e
      log_warn("Invalid JSON response: #{e.message}")
      nil
    end

    def response_content(response)
      return response[:content].to_s.strip if response.is_a?(Hash) && response[:content]
      return response['content'].to_s.strip if response.is_a?(Hash) && response['content']

      response.to_s.strip
    end

    def valid_schema?(payload)
      payload.is_a?(Hash) && exact_keys?(payload) && valid_values?(payload)
    end

    def exact_keys?(payload)
      payload.keys.sort == RESPONSE_KEYS
    end

    def valid_values?(payload)
      VALIDATORS.all? { |key, validator| validator.call(payload[key]) }
    end

    def system_prompt
      <<~PROMPT
        You are a market-structure analyst.

        You DO NOT predict price.
        You DO NOT generate trades.
        You DO NOT invent signals.

        You are given fully computed, rule-based Smart Money Concepts (SMC)
        and AVRZ structure across multiple timeframes.

        Your job is to:
        1. Infer the overall market bias and regime from the structure
        2. Decide which option direction is ALLOWED (CE only, PE only, or neither)
        3. Validate whether the engine decision is ALIGNED with that bias
        4. Provide a concise, factual explanation strictly based on the data

        Rules:
        - Use ONLY the provided data
        - Do NOT assume missing information
        - If structure is mixed or ranging, prefer "neither"
        - HTF (60m) dominates MTF (15m), which dominates LTF (5m)
        - Liquidity sweeps + OB + premium/discount increase confidence
        - AVRZ strengthens reversal confirmation but does not override HTF trend
        - If decision conflicts with HTF trend -> mark invalid

        You MUST respond in valid JSON only.
        No prose. No markdown. No extra keys.
      PROMPT
    end

    def user_prompt
      <<~PROMPT
        Analyze the following structured market data and return your assessment.

        Tasks:
        - Determine market_bias
        - Determine market_regime
        - Determine directional_allowance
        - Validate the engine decision
        - Estimate confidence (0-100)
        - Suggest expected trade duration
        - Provide a short explanation based ONLY on the structure

        Structured input:
        #{structured_input}

        Required output schema (strict):
        {
          "market_bias": "bullish | bearish | range",
          "market_regime": "trending | rangebound",
          "directional_allowance": "CE_ONLY | PE_ONLY | NEITHER",
          "decision_alignment": "ALIGNED | CONFLICT | NO_TRADE_OK",
          "decision_valid": true,
          "confidence": 0,
          "suggested_duration": "1m | 5m | 15m | 30m | 60m",
          "explanation": "concise factual reasoning"
        }
      PROMPT
    end

    def structured_input
      JSON.pretty_generate(@initial_data)
    end
  end
end
