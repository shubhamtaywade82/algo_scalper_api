# frozen_string_literal: true

require 'ollama_client'
require 'yaml'
require_relative '../utils/logger'

module AutoExp
  class LlmPlanner
    MODEL = 'qwen2.5:3b'

    SCHEMA = {
      'type' => 'object',
      'required' => %w[parameter value reason],
      'properties' => {
        'parameter' => {
          'type' => 'string',
          'enum' => [
            'entry.range_expansion_threshold',
            'entry.atr_rising_lookback',
            'strike_selection.delta_target',
            'exit.mfe_ratio_nifty',
            'exit.initial_stop',
            'risk.max_trades_per_day'
          ]
        },
        'value' => { 'type' => 'number' },
        'reason' => { 'type' => 'string' }
      }
    }.freeze

    def initialize
      @client = Ollama::Client.new
    end

    def propose(results:, config:)
      prompt = build_prompt(results, config)

      begin
        response = @client.generate(
          model: MODEL,
          prompt: prompt,
          schema: SCHEMA
        )
        # The ollama-client gem returns a hash if schema is provided
        response
      rescue StandardError => e
        ::Utils::Logger.error('auto_exp.llm_failed', error: e.message)
        nil
      end
    end

    private

    def build_prompt(results, config)
      history = results.last(10).map do |r|
        "pf=#{r[:profit_factor]} dd=#{r[:drawdown]}"
      end.join("\n")

      <<~PROMPT
        You are optimizing a trading strategy.

        Goal:
        Increase profit_factor while avoiding drawdown increases.

        Recent experiment results:
        #{history.empty? ? 'No previous results.' : history}

        Current configuration:
        #{config.to_yaml}

        Suggest ONE parameter change.

        Output JSON only.
      PROMPT
    end
  end
end
