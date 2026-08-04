# frozen_string_literal: true

require "fileutils"

module Research
  class NotebookGenerator
    # Generates a reproducible quant research notebook for a hypothesis experiment.
    # Saves markdown files under data/research/notebooks/EXP-XXX.md.
    def self.generate(exp_id, question, hypothesis, trades, validation_reports, output_dir = "data/research/notebooks")
      FileUtils.mkdir_p(output_dir)

      # 1. Model expected outcome distributions
      matching_trades = trades.select { |t| trades_matching_filter?(t, hypothesis) }

      mfe_vals = matching_trades.filter_map { |t| t.dig(:strikes, "ATM", :mfe_pct) }
      mae_vals = matching_trades.filter_map { |t| t.dig(:strikes, "ATM", :mae_pct) }
      decay_vals = matching_trades.filter_map { |t| t.dig(:strikes, "ATM", :drawdown_from_peak_pct) }
      hold_vals = matching_trades.filter_map { |t| t.dig(:strikes, "ATM", :exits, :hybrid_divergence, :holding_time_minutes) }

      mfe_dist = DistributionModel.build(mfe_vals)
      mae_dist = DistributionModel.build(mae_vals)
      decay_dist = DistributionModel.build(decay_vals)
      hold_dist = DistributionModel.build(hold_vals)

      # 2. Compute Evidence Scorecard
      evidence = EvidenceCalculator.calculate(matching_trades, validation_reports, hypothesis.p_value)

      # 3. Determine detailed verdict and reasoning
      verdict_text = hypothesis.verdict.to_s.tr('_', ' ').upcase
      reasons = []
      reasons << hypothesis.reason if hypothesis.reason

      if hypothesis.verdict == :accepted
        reasons << "Strong composite evidence score of #{evidence[:score]}/100."
        reasons << "Highly stable out-of-sample replication (OOS score: #{evidence[:details][:oos_replication_score]}/100)."
        reasons << "High statistical confidence limit (score: #{evidence[:details][:significance_confidence_score]}/100)."
      elsif hypothesis.verdict == :rejected
        reasons << "Poor composite evidence score of #{evidence[:score]}/100."
        reasons << "Small matching sample size (sample score: #{evidence[:details][:sample_size_score]}/100)." if evidence[:details][:sample_size_score] < 40
        reasons << "High return variance / poor stability (stability score: #{evidence[:details][:return_stability_score]}/100)." if evidence[:details][:return_stability_score] < 40
        reasons << "Significant Out-of-Sample return leakage (OOS score: #{evidence[:details][:oos_replication_score]}/100)." if evidence[:details][:oos_replication_score] < 50
      end

      # 4. Compile Markdown
      md = <<~MARKDOWN
        # Quant Research Experiment Notebook [#{exp_id}]
        **Timestamp**: #{Time.zone.now}
        **Research Question**: #{question}

        ## 📋 Metadata Context
        - **Hypothesis Rule**: `#{hypothesis.description}`
        - **Research Version**: `V7.0`
        - **Feature Version**: `V7.0`
        - **Exit Strategy Version**: `V7.0`
        - **Total Baseline Dataset**: #{trades.size} sessions
        - **Hypothesis Sample Size**: #{hypothesis.sample_size} matches

        ## 🧠 Outcome Distributions (95% Confidence Intervals)
        Below is the probabilistic modeling of trade outcomes for the ATM option contract:

        | Parameter | Mean | Median | Std Dev | 95% Confidence Interval |
        | :--- | :---: | :---: | :---: | :---: |
        | **MFE %** | #{mfe_dist[:mean]}% | #{mfe_dist[:median]}% | #{mfe_dist[:std_dev]}% | [#{mfe_dist[:ci_lower]}%, #{mfe_dist[:ci_upper]}%] |
        | **MAE %** | #{mae_dist[:mean]}% | #{mae_dist[:median]}% | #{mae_dist[:std_dev]}% | [#{mae_dist[:ci_lower]}%, #{mae_dist[:ci_upper]}%] |
        | **Decay %** | #{decay_dist[:mean]}% | #{decay_dist[:median]}% | #{decay_dist[:std_dev]}% | [#{decay_dist[:ci_lower]}%, #{decay_dist[:ci_upper]}%] |
        | **Hold Time (Mins)** | #{hold_dist[:mean]} | #{hold_dist[:median]} | #{hold_dist[:std_dev]} | [#{hold_dist[:ci_lower]}, #{hold_dist[:ci_upper]}] |

        ## 📊 Evidence Scorecard
        We aggregate multiple quantitative vectors to evaluate the validity of the hypothesis:

        - **Composite Evidence Score**: **#{evidence[:score]} / 100**
        - **Sub-Metric Scorecard**:
          - Sample Size Robustness: `#{evidence[:details][:sample_size_score]} / 100`
          - Return Sharpe Stability: `#{evidence[:details][:return_stability_score]} / 100`
          - Walk-Forward OOS Replication: `#{evidence[:details][:oos_replication_score]} / 100`
          - Bootstrap Confidence Stability: `#{evidence[:details][:bootstrap_stability_score]} / 100`
          - Binomial Significance Confidence: `#{evidence[:details][:significance_confidence_score]} / 100`

        ## ⚖️ Final Verdict
        ### Verdict: **`#{verdict_text}`**

        #### Justification Reasons:
        #{reasons.map { |r| "* #{r}" }.join("\n")}

        ---
        *Reproducible research notebook compiled automatically by the Market Research Operating System (V7).*
      MARKDOWN

      # Write file
      file_path = File.join(output_dir, "#{exp_id}.md")
      File.write(file_path, md)
      file_path
    end

    def self.trades_matching_filter?(trade, hypothesis)
      # Extract description or logic to filter trades matching hypothesis filter.
      # Because filter_proc is not public or easily queried, we re-verify based on hypothesis description keywords:
      desc = hypothesis.description.downcase
      if desc.include?("gap-down")
        trade[:breakout_type] == :bearish &&
          trade[:gap_pct].to_f < -0.15 &&
          trade[:vwap_dist].to_f.negative?
      elsif desc.include?("inside day")
        trade[:is_inside_day] &&
          trade[:or_width].to_f < 35.0 &&
          trade[:adx].to_f > 20.0
      elsif desc.include?("wide or")
        trade[:or_width].to_f > 50.0
      elsif desc.include?("velocity")
        trade[:ignition] && trade[:ignition][:ignition_velocity].to_f.abs >= 3.0
      else
        true
      end
    end
  end
end
