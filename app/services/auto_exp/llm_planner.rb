# frozen_string_literal: true

module AutoExp
  class LlmPlanner
    def model
      ENV['OLLAMA_MODEL'] || "llama3.2:3b"
    end

    SCHEMA = {
      "type" => "object",
      "required" => %w[parameter value reason],
      "properties" => {
        "parameter" => {
          "type" => "string",
          "enum" => [
            "entry.range_expansion_threshold",
            "entry.atr_rising_lookback",
            "strike_selection.delta_target",
            "exit.mfe_ratio_nifty",
            "exit.initial_stop",
            "risk.max_trades_per_day"
          ]
        },
        "value" => { "type" => "number" },
        "reason" => { "type" => "string" }
      }
    }.freeze

    def initialize
      @client = Services::Ai::OllamaClient.instance
    end

    def propose(results:, config:)
      prompt = build_prompt(results, config)

      @client.generate(
        model: model,
        prompt: prompt,
        schema: SCHEMA
      )
    end

    private

    def build_prompt(results, config)
      history = (results || []).last(10)
                              .map { |r| "pf=#{r[:profit_factor]} dd=#{r[:drawdown]} win_rate=#{r[:win_rate]}" }
                              .join("\n")

      <<~PROMPT
        You are optimizing a trading strategy.

        Goal:
        Increase profit_factor while avoiding drawdown increases.

        Recent experiment results:
        #{history.empty? ? 'No previous results.' : history}

        Current configuration:
        #{config.to_yaml}

        Suggest ONE parameter change. Ensure the value is within reasonable bounds:
        - entry.range_expansion_threshold: 1.2..2.0
        - entry.atr_rising_lookback: 1..5
        - strike_selection.delta_target: 0.4..0.6
        - exit.mfe_ratio_nifty: 0.2..0.6
        - exit.initial_stop: 0.08..0.20
        - risk.max_trades_per_day: 1..5

        Output JSON only.
      PROMPT
    end
  end
end
