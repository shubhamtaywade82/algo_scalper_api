# frozen_string_literal: true

module Research
  class OpportunityScorer
    # Calculates a composite Expected Opportunity Score (EOS) for a trade event.
    # Weighs reward (MFE), risk (MAE), and slippage/decay (drawdown).
    # @param expansion_ctx [Hash] Option expansion metrics
    # @return [Integer] Expected Opportunity Score (0 to 100)
    def self.score(expansion_ctx)
      mfe = expansion_ctx[:mfe_pct] || 0.0
      mae = expansion_ctx[:mae_pct] || 0.0
      decay = expansion_ctx[:drawdown_from_peak_pct] || 0.0

      # Formula: Reward vs Risk weighted by decay giveback
      reward_weight = mfe * 1.2
      risk_penalty = mae.abs * 1.5
      decay_penalty = decay * 0.4

      raw_score = reward_weight - risk_penalty - decay_penalty

      # Map negative/zero bounds to a positive 0-100 score
      # Add base score components if trade was profitable
      base_bonus = mfe >= 30.0 ? 30 : 0
      final_score = (raw_score + base_bonus).round

      [[final_score, 100].min, 0].max
    end
  end
end
