# frozen_string_literal: true

module Research
  class Scheduler
    # Executes the nightly quant research pipeline.
    #
    # Pipeline:
    #   1. Data Quality Audit
    #   2. Feature Registry seed (idempotent)
    #   3. Dataset snapshot (immutable fingerprint)
    #   4. Research Engine run (with cost tracking)
    #   5. Hypothesis evaluation → Evidence scoring → Notebook generation
    #   6. Experiment Registry logging (with dataset ID + cost)
    #   7. Edge promotion (if evidence >= 65, with portfolio metadata)
    #   8. Edge revalidation (drift monitoring)
    #
    # @param underlying [String] Symbol of index spot, e.g. "NIFTY"
    # @param days_count [Integer] Number of history days to run
    # @return [Hash] Summary of the run
    def self.run_nightly(underlying = "NIFTY", days_count = 365)
      pipeline_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      Rails.logger.info("[MROS::Scheduler] ═══ Nightly research pipeline starting for #{underlying} ═══")

      # 1. Data Quality Audit
      Rails.logger.info("[MROS::Scheduler] Phase 1: Data quality audit...")
      audits = Research::DataQualityEngine.audit_recent(underlying, days: days_count)
      failed_dates = audits.select { |a| a[:status] == "fail" }
      Rails.logger.warn("[MROS::Scheduler] #{failed_dates.size} dates failed data quality checks.") if failed_dates.any?

      # 2. Feature Registry seed (idempotent)
      Rails.logger.info("[MROS::Scheduler] Phase 2: Feature registry seed...")
      Research::FeatureRegistry.seed!

      # 3. Dataset snapshot — immutable fingerprint for reproducibility
      Rails.logger.info("[MROS::Scheduler] Phase 3: Dataset snapshot...")
      total_candles = audits.sum { |a| a[:total_candles] }
      end_date = Date.current
      start_date = end_date - days_count.days
      dataset_id = Research::ExperimentRegistry.snapshot_dataset(
        symbol: underlying,
        start_date: start_date,
        end_date: end_date,
        session_count: audits.size,
        candle_count: total_candles
      )

      # 4. Run Research Engine (with cost tracking)
      Rails.logger.info("[MROS::Scheduler] Phase 4: Research engine run...")
      engine_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      report = Research::First15mEngine.run(symbol: underlying, lookback_days: days_count)
      engine_elapsed_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - engine_start) * 1000).round
      Rails.logger.info("[MROS::Scheduler] Research engine completed in #{engine_elapsed_ms}ms")

      if report.blank? || !report.key?(:hypotheses)
        Rails.logger.warn("[MROS::Scheduler] Pipeline yielded no events or failed to fetch data.")
        return { status: :failed, reason: "no_data", audits: audits, dataset_id: dataset_id }
      end

      trades = report[:trades] || []
      features_used = Research::FeatureRegistry::FEATURE_CATALOGUE.size

      # 5. Hypothesis evaluation + Evidence scoring + Notebook generation + Registration
      Rails.logger.info("[MROS::Scheduler] Phase 5: Hypothesis evaluation and experiment registration...")
      hypotheses = Research::HypothesisEngine.run(trades)

      questions = {
        "Gap-down (< -0.15%) + entry below VWAP -> Bearish PE ATM MFE >= 30%" =>
          { id: "Q-001", text: "Can Gap Down + entry below VWAP predict PE ATM option expansion >= 30%?" },
        "Inside Day + Narrow OR (< 35 pts) + ADX > 20 -> Sustained breakout" =>
          { id: "Q-002", text: "Does Inside Day compression with narrow opening range lead to sustained breakouts?" },
        "Wide OR (> 50 pts) -> Breakout fails / mean reverts" =>
          { id: "Q-003", text: "Do wide opening ranges (> 50 points) trigger breakout failures and mean reversion?" },
        "High Ignition Velocity (> 3.0 pts/min) -> Option MFE >= 30%" =>
          { id: "Q-004", text: "Does high initial ignition velocity translate to >= 30% ATM option premium expansion?" }
      }

      notebooks = []
      experiments = []

      hypotheses.each_with_index do |h, idx|
        exp_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        exp_id = format("EXP-%05d", idx + 1)
        q_meta = questions[h.description] || { id: "Q-#{idx + 1}", text: "Automated hypothesis evaluation" }
        exit_val = report[:statistical_validation]&.[](:hybrid_divergence) || {}

        # Generate notebook
        notebook_path = Research::NotebookGenerator.generate(
          exp_id, q_meta[:text], h, trades, exit_val
        )
        notebooks << notebook_path

        # Compute evidence
        matching_trades = trades.select { |t| NotebookGenerator.send(:trades_matching_filter?, t, h) }
        evidence = Research::EvidenceCalculator.calculate(matching_trades, exit_val, h.p_value)

        exp_elapsed_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - exp_start) * 1000).round

        # Register with dataset ID and cost
        Research::ExperimentRegistry.register(
          experiment_id: exp_id,
          question_id: q_meta[:id],
          question_text: q_meta[:text],
          hypothesis: h,
          dataset_id: dataset_id,
          dataset_size: trades.size,
          evidence: evidence,
          notebook_path: notebook_path,
          cost: { cpu_time_ms: exp_elapsed_ms, rows_processed: trades.size, features_used: features_used }
        )

        verdict = h.verdict.to_s
        experiments << { experiment_id: exp_id, evidence_score: evidence[:score], verdict: verdict }

        # Promote to Edge with portfolio metadata if hypothesis is accepted and evidence is strong
        next unless h.verdict == :accepted && evidence[:score] >= 65

        edge_id = format("EDGE-%03d", idx + 1)
        Research::EdgeRegistry.register(
          edge_id: edge_id,
          experiment_id: exp_id,
          description: h.description,
          evidence_score: evidence[:score],
          confidence: (1.0 - h.p_value).round(4),
          regime: "neutral",
          sample_size: h.sample_size,
          portfolio: {
            expected_return: h.expectancy_r,
            win_probability: h.success_rate / 100.0,
            expected_drawdown: nil, # computed once we have MAE distributions
            confidence_interval: nil,
            capacity: "unknown",
            expiry_sensitivity: "weekly",
            market: underlying
          }
        )
      end

      # 6. Revalidate existing edges
      Rails.logger.info("[MROS::Scheduler] Phase 6: Revalidating existing edges...")
      existing_edges = Research::EdgeRegistry.list(status: "accepted") + Research::EdgeRegistry.list(status: "production")
      revalidation_results = existing_edges.map do |edge|
        Research::EdgeRegistry.revalidate(edge[:edge_id], edge[:evidence_score])
      end

      pipeline_elapsed_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - pipeline_start) * 1000).round
      Rails.logger.info("[MROS::Scheduler] ═══ Nightly pipeline complete (#{pipeline_elapsed_ms}ms) ═══")

      {
        status: :success,
        dataset_id: dataset_id,
        total_opportunities: report[:total_trade_opportunities],
        pipeline_cost_ms: pipeline_elapsed_ms,
        data_quality: {
          audited: audits.size,
          passed: audits.count { |a| a[:status] == "pass" },
          warnings: audits.count { |a| a[:status] == "warning" },
          failed: audits.count { |a| a[:status] == "fail" }
        },
        experiments: experiments,
        notebooks_generated: notebooks,
        edges_revalidated: revalidation_results.size
      }
    end
  end
end
