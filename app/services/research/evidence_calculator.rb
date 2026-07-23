# frozen_string_literal: true

module Research
  class EvidenceCalculator
    # Calculates a scientific Evidence Score scorecard (0 to 100) for a hypothesis run.
    # @param trades [Array<Hash>] Trade opportunities matching the hypothesis
    # @param validation_reports [Hash] Statistical validations (CI, IS/OOS splits)
    # @param p_value [Float] Binomial significance p-value
    # @return [Hash] Scorecard with sub-metrics and composite Evidence Score
    def self.calculate(trades, validation_reports, p_value)
      return {
        score: 0,
        details: {
          sample_size_score: 0.0,
          return_stability_score: 0.0,
          oos_replication_score: 0.0,
          bootstrap_stability_score: 0.0,
          significance_confidence_score: 0.0
        }
      } if trades.empty?

      sample_size = trades.size
      returns = trades.map { |t| t[:strikes]["ATM"][:exits][:hybrid_divergence][:return_pct] }
      mean_ret = returns.sum / sample_size

      # 1. Sample Size Score (0 to 100)
      # Baseline: 100 trades for a full score of 100
      sample_score = [[(sample_size.to_f / 100.0) * 100.0, 100.0].min, 0.0].max

      # 2. Return Stability Score (0 to 100)
      # Derived from trade-level Sharpe ratio (expectancy / standard deviation)
      stability_score = 0.0
      if sample_size > 1
        avg = returns.sum / sample_size
        variance = returns.sum { |r| (r - avg)**2 } / (sample_size - 1)
        std_dev = Math.sqrt(variance)
        if std_dev.positive? && avg.positive?
          sharpe = avg / std_dev
          # Sharpe of 0.5+ trade-level translates to 100 score
          stability_score = [[(sharpe / 0.5) * 100.0, 100.0].min, 0.0].max
        end
      end

      # 3. Walk-Forward OOS Replication Score (0 to 100)
      # Measures how well Out-of-Sample return matches In-Sample return
      oos_score = 0.0
      is_ret = validation_reports&.[](:split_validation)&.[](:is_avg_return_pct) || 0.0
      oos_ret = validation_reports&.[](:split_validation)&.[](:oos_avg_return_pct) || 0.0

      if is_ret.positive?
        if oos_ret >= is_ret
          oos_score = 100.0
        elsif oos_ret.positive?
          oos_score = (oos_ret / is_ret) * 100.0
        end
      end

      # 4. Bootstrap Stability Score (0 to 100)
      # Measures confidence interval width relative to mean return
      bootstrap_score = 0.0
      ci = validation_reports&.[](:bootstrap)&.[](:expected_return_95_ci)
      if ci && ci[0] && ci[1] && mean_ret.positive?
        ci_width = ci[1] - ci[0]
        # Penalty if CI width is wider than twice the mean return
        bootstrap_score = [[100.0 - ((ci_width / (2.0 * mean_ret)) * 100.0), 100.0].min, 0.0].max
      end

      # 5. Significance Confidence Score (0 to 100)
      # p-value boundary check (1 - p_value)
      confidence_score = [[(1.0 - p_value) * 100.0, 100.0].min, 0.0].max

      # Weighted Composite Evidence Score
      composite = (0.2 * sample_score) +
                  (0.2 * stability_score) +
                  (0.2 * oos_score) +
                  (0.2 * bootstrap_score) +
                  (0.2 * confidence_score)

      {
        score: composite.round,
        details: {
          sample_size_score: sample_score.round(2),
          return_stability_score: stability_score.round(2),
          oos_replication_score: oos_score.round(2),
          bootstrap_stability_score: bootstrap_score.round(2),
          significance_confidence_score: confidence_score.round(2)
        }
      }
    end
  end
end
