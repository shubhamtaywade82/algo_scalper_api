# frozen_string_literal: true

module Ai
  module Agents
    # Level 2 (bounded autonomous) — the one agent granted the `apply_config`
    # capability (see AgentSupervisor). Reads live regime + option-chain +
    # risk state via Ai::DynamicConfig::ContextBuilder, asks Ollama for
    # parameter changes scoped to Ai::DynamicConfig::ResultParser::KNOWN_PARAMS,
    # and applies the resulting patch directly to AlgoConfig::DocumentStore —
    # no human step. Only affects entries opened after the patch lands
    # (Positions::ExitConfigResolver pins config at entry). Applies only
    # while AlgoConfig.paper_trading_enabled? — going live still requires
    # the same manual flip as today, this agent does not touch that gate.
    # While the circuit breaker is tripped or there's a recent losing streak,
    # ResultParser enforces (in code, not just via prompt instruction) that
    # only risk-reducing moves on risk-lever params are accepted.
    class DynamicConfigAgent < BaseAgent
      AUTHORITY_LEVEL = :level_2
      SCHEMA_PATH = Rails.root.join('config/ai_dynamic_config_schema.json')
      CONSECUTIVE_LOSS_STRESS_THRESHOLD = 2

      private

      def perform(index_key:)
        index_key = index_key.to_s.upcase
        context = Ai::DynamicConfig::ContextBuilder.call(index_key: index_key)
        raw = call_ai_generate(Ai::DynamicConfig::PromptBuilder.call(context: context))
        return no_data_result(index_key, 'ollama unavailable') unless raw

        parsed = Ai::DynamicConfig::ResultParser.call(
          raw,
          index_key: index_key,
          current_config: context[:current_config],
          stressed: stressed?(context[:risk])
        )
        applied = apply_patch(parsed[:proposed_patch], index_key: index_key)

        {
          decision_type: 'dynamic_config',
          confidence: parsed[:parameter_changes].empty? ? 0.0 : 1.0,
          output: {
            index_key: index_key,
            market_assessment: parsed[:market_assessment],
            parameter_changes: parsed[:parameter_changes],
            applied: applied
          }
        }
      rescue Ai::DynamicConfig::ResultParser::ParseError, Ai::DynamicConfig::ResultParser::SchemaError => e
        no_data_result(index_key, "parse error: #{e.message}")
      end

      def call_ai_generate(prompt)
        client = Services::Ai::OllamaClient.instance
        return nil unless client.enabled?

        schema = JSON.parse(File.read(SCHEMA_PATH))
        client.generate(prompt: prompt, model: client.preferred_text_model, schema: schema)
      rescue StandardError => e
        Rails.logger.error("[DynamicConfigAgent] AI generation failed: #{e.message}")
        nil
      end

      def apply_patch(patch, index_key:)
        return false if patch.blank?
        return false unless AlgoConfig.paper_trading_enabled?
        return false unless AgentSupervisor.instance.capability_granted?(self.class.agent_name, :apply_config)

        AlgoConfig::DocumentStore.apply_deep_merge_patch!(
          patch,
          source: 'dynamic_config_agent',
          actor: 'dynamic_config_agent',
          metadata: { index_key: index_key }
        )
        true
      end

      def stressed?(risk)
        return false unless risk

        risk[:circuit_breaker_tripped] || risk[:recent_consecutive_losses].to_i >= CONSECUTIVE_LOSS_STRESS_THRESHOLD
      end

      def no_data_result(index_key, reason)
        { decision_type: 'dynamic_config', confidence: 0.0, output: { index_key: index_key, note: reason } }
      end
    end
  end
end
