# frozen_string_literal: true

require 'timeout'

module Ai
  class AlphaGate
    # Minimum probability of a sound trade at which the decision model allows it.
    DEFAULT_ALLOW_THRESHOLD = 0.5

    # The one question put to a decision model. It carries the three checks the chat
    # prompt names and points at the state fields that hold them.
    SOUNDNESS_QUESTION = {
      'type' => 'noul',
      'instructions' => 'The system is about to BUY this index option for an intraday scalping trade, as described by this state. ' \
                        'Is the trade logically sound by typical intraday index options scalping principles? ' \
                        'Judge the stop-loss distance (`stop_loss_distance_pct`), the time of day (`time_ist`) ' \
                        'and the strike distance (`strike_distance_pct`).',
      'criteria' => {
        'true' => 'The trade is sound: a sensible stop-loss distance, a usable time of day and a strike close enough to the index.',
        'false' => 'The trade is not sound: a stop-loss too tight or too wide, a poor time of day, or a strike too far from the index.'
      }
    }.freeze

    # Evaluates if an Alpha Engine signal should be executed.
    #
    # @param signal [Hash] The alpha signal
    # @return [Boolean] true if allowed, false if blocked
    def self.approve?(signal)
      # Check if AI gate is enabled in config
      gate_config = AlgoConfig.fetch[:alpha_strategies]&.dig(:ai_gate) || {}
      return true unless gate_config[:enabled]

      return decision_model_allows?(signal) if Services::Ai::DecisionClient.model

      client = Services::Ai::OllamaClient.instance
      unless client.enabled?
        Rails.logger.warn "[Ai::AlphaGate] Ollama disabled, failing OPEN (allowing trade)."
        return true
      end

      model = LLMSettings.analysis_model

      prompt = <<~PROMPT
        You are a strict risk management AI for an algorithmic options scalping system.
        The system's Alpha Engine is proposing the following options trade:

        - Instrument: #{signal[:index_key].to_s.upcase}
        - Option Direction: #{signal[:direction].to_s.upcase} (We are BUYING this option)
        - Strategy Source: #{signal[:alpha_source]}
        - Current Index Price: ₹#{signal[:underlying_ltp]}
        - Target Option Strike: ₹#{signal[:strike]}
        - Stop Loss (Index level): ₹#{signal[:stop_loss]}
        - Target (Index level): ₹#{signal[:target]}
        - Engine Confidence: #{(signal[:confidence].to_f * 100).round(1)}%
        - Time: #{Time.current.in_time_zone('Asia/Kolkata').strftime('%H:%M IST')}

        Is this trade logically sound given typical intraday index options scalping principles?
        Consider the stop-loss distance, the time of day, and the strike distance.

        Respond with ONLY ONE WORD: ALLOW or BLOCK.
      PROMPT

      response = Timeout.timeout(8) do
         client.chat(
           messages: [
             { role: 'system', content: 'You are a strict risk management AI. Reply with exactly one word: ALLOW or BLOCK.' },
             { role: 'user', content: prompt }
           ],
           model: model,
           temperature: 0.1
         )
      end

      # OllamaClient#chat returns nil when the call failed. That is a failed check,
      # not a model that allowed the trade.
      if response.blank?
        Rails.logger.warn "[Ai::AlphaGate] No reply from #{model}, failing OPEN (allowing trade)."
        return true
      end

      result = response.to_s.upcase.strip

      if result.include?('BLOCK')
        Rails.logger.warn "[Ai::AlphaGate] Trade BLOCKED by AI Risk Manager for #{signal[:index_key]}"
        false
      else
        Rails.logger.info "[Ai::AlphaGate] Trade ALLOWED by AI Risk Manager for #{signal[:index_key]}"
        true
      end
    rescue Timeout::Error
      Rails.logger.warn "[Ai::AlphaGate] Timeout waiting for Ollama, failing OPEN (allowing trade)."
      true
    rescue StandardError => e
      Rails.logger.warn "[Ai::AlphaGate] Error evaluating signal: #{e.message}, failing OPEN."
      true
    end

    # Decision-model path (OLLAMA_DECISION_MODEL). The model returns the probability
    # that the trade is sound, so there is no word to parse. Any failure raises and
    # is failed OPEN by the rescues in +approve?+, exactly like the chat path.
    def self.decision_model_allows?(signal)
      client = Services::Ai::DecisionClient.instance
      unless client.enabled?
        Rails.logger.warn "[Ai::AlphaGate] Decision model #{client.model} unavailable, failing OPEN (allowing trade)."
        return true
      end

      score = Timeout.timeout(8) do
        client.probability(state: decision_state(signal), question: SOUNDNESS_QUESTION)
      end
      threshold = allow_threshold
      allowed   = score.probability >= threshold
      message   = "[Ai::AlphaGate] Trade #{allowed ? 'ALLOWED' : 'BLOCKED'} by decision model #{client.model} for " \
                  "#{signal[:index_key]}: P(sound)=#{score.probability.round(4)} " \
                  "(threshold #{threshold}, #{score.input_tokens || 'unknown'} input tokens)"
      if allowed
        Rails.logger.info message
      else
        Rails.logger.warn message
      end
      allowed
    end

    # What the decision model sees: the fields of the chat prompt, plus the distances
    # the prompt asks the model to judge, computed here so the model does not have to.
    def self.decision_state(signal)
      ltp = signal[:underlying_ltp].to_f
      state = {
        'instrument' => signal[:index_key].to_s.upcase,
        'option_direction' => signal[:direction].to_s.upcase,
        'option_side' => 'BUY',
        'strategy_source' => signal[:alpha_source].to_s,
        'index_price' => ltp,
        'strike' => signal[:strike].to_f,
        'stop_loss_index_level' => signal[:stop_loss].to_f,
        'target_index_level' => signal[:target].to_f,
        'engine_confidence_pct' => (signal[:confidence].to_f * 100).round(1),
        'time_ist' => Time.current.in_time_zone('Asia/Kolkata').strftime('%H:%M')
      }
      {
        'stop_loss_distance_pct' => signal[:stop_loss],
        'strike_distance_pct' => signal[:strike],
        'target_distance_pct' => signal[:target]
      }.each do |key, level|
        distance = distance_pct(level, from: ltp)
        state[key] = distance if distance
      end
      state
    end

    def self.distance_pct(level, from:)
      value = level.to_f
      return unless from.positive? && value.positive?

      (((value - from).abs / from) * 100).round(2)
    end

    # OLLAMA_DECISION_ALLOW_THRESHOLD must lie in (0, 1]; anything else falls back to
    # the default and says so, instead of quietly allowing or blocking everything.
    def self.allow_threshold
      raw = ENV['OLLAMA_DECISION_ALLOW_THRESHOLD'].presence
      return DEFAULT_ALLOW_THRESHOLD if raw.nil?

      value = Float(raw)
      return value if value.positive? && value <= 1

      raise ArgumentError, 'out of range'
    rescue ArgumentError
      Rails.logger.warn "[Ai::AlphaGate] OLLAMA_DECISION_ALLOW_THRESHOLD must be within (0, 1], got #{raw.inspect}; using #{DEFAULT_ALLOW_THRESHOLD}."
      DEFAULT_ALLOW_THRESHOLD
    end
  end
end
