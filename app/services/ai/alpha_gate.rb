# frozen_string_literal: true

require 'timeout'

module Ai
  class AlphaGate
    # Evaluates if an Alpha Engine signal should be executed.
    # 
    # @param signal [Hash] The alpha signal
    # @return [Boolean] true if allowed, false if blocked
    def self.approve?(signal)
      # Check if AI gate is enabled in config
      gate_config = AlgoConfig.fetch[:alpha_strategies]&.dig(:ai_gate) || {}
      return true unless gate_config[:enabled]

      client = Services::Ai::OllamaClient.instance
      unless client.enabled?
        Rails.logger.warn "[Ai::AlphaGate] Ollama disabled, failing OPEN (allowing trade)."
        return true 
      end
      
      model = ENV['OLLAMA_MODEL'] || client.selected_model || 'llama3.2:3b'
      
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
  end
end
