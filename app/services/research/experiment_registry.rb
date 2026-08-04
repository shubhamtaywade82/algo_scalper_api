# frozen_string_literal: true

module Research
  # Records every research experiment permanently. No experiment is ever lost.
  # Each experiment links a research question to an immutable dataset snapshot,
  # hypothesis, evidence score, research cost, and notebook for full reproducibility.
  class ExperimentRegistry
    # Register a completed experiment with cost tracking and dataset fingerprint.
    # @param experiment_id [String] e.g. "EXP-00042"
    # @param question_id [String] e.g. "Q-001"
    # @param question_text [String]
    # @param hypothesis [Research::HypothesisEngine::Hypothesis]
    # @param dataset_id [String] immutable dataset snapshot ID e.g. "DS-00001"
    # @param dataset_size [Integer]
    # @param evidence [Hash] output from EvidenceCalculator
    # @param notebook_path [String]
    # @param cost [Hash] { cpu_time_ms:, rows_processed:, features_used: }
    # @return [String] experiment_id
    def self.register(experiment_id:, question_id:, question_text:, hypothesis:,
                      dataset_id:, dataset_size:, evidence:, notebook_path:,
                      cost: {})
      verdict = hypothesis.verdict.to_s
      rejection_reason = hypothesis.reason || (%w[rejected needs_more_samples insufficient_evidence].include?(verdict) ? build_rejection_reason(evidence) : nil)

      conn = ActiveRecord::Base.connection
      conn.execute(ActiveRecord::Base.sanitize_sql_array([
                                                           <<~SQL.squish,
                                                             INSERT INTO research_experiment_registry
                                                             (experiment_id, question_id, question_text, hypothesis_description,
                                                              dataset_id, dataset_range, dataset_size, evidence_score, evidence_details,
                                                              distributions, verdict, notebook_path, rejection_reason,
                                                              cpu_time_ms, rows_processed, features_used,
                                                              created_at, updated_at)
                                                             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, '{}', ?, ?, ?, ?, ?, ?, NOW(), NOW())
                                                             ON CONFLICT (experiment_id) DO UPDATE SET
                                                               evidence_score = EXCLUDED.evidence_score,
                                                               evidence_details = EXCLUDED.evidence_details,
                                                               verdict = EXCLUDED.verdict,
                                                               rejection_reason = EXCLUDED.rejection_reason,
                                                               cpu_time_ms = EXCLUDED.cpu_time_ms,
                                                               rows_processed = EXCLUDED.rows_processed,
                                                               features_used = EXCLUDED.features_used,
                                                               dataset_id = EXCLUDED.dataset_id,
                                                               updated_at = NOW()
                                                           SQL
                                                           experiment_id,
                                                           question_id,
                                                           question_text,
                                                           hypothesis.description,
                                                           dataset_id,
                                                           dataset_id, # also stored in dataset_range for backward compatibility
                                                           dataset_size,
                                                           evidence[:score],
                                                           evidence[:details].to_json,
                                                           verdict,
                                                           notebook_path,
                                                           rejection_reason,
                                                           cost[:cpu_time_ms].to_i,
                                                           cost[:rows_processed].to_i,
                                                           cost[:features_used].to_i
                                                         ]))

      Rails.logger.info(
        "[MROS::ExperimentRegistry] Registered #{experiment_id} — " \
        "verdict: #{verdict} (#{evidence[:score]}/100), cost: #{cost[:cpu_time_ms]}ms"
      )
      experiment_id
    end

    # Create an immutable dataset snapshot and return its ID.
    # @param symbol [String]
    # @param start_date [Date]
    # @param end_date [Date]
    # @param session_count [Integer]
    # @param candle_count [Integer]
    # @return [String] dataset_id e.g. "DS-00001"
    def self.snapshot_dataset(symbol:, start_date:, end_date:, session_count:, candle_count:)
      fingerprint = Digest::SHA256.hexdigest("#{symbol}|#{start_date}|#{end_date}|#{session_count}|#{candle_count}")

      # Check if this exact snapshot already exists
      conn = ActiveRecord::Base.connection
      existing = conn.select_value(
        ActiveRecord::Base.sanitize_sql_array([
                                                "SELECT dataset_id FROM research_dataset_snapshots WHERE fingerprint = ?", fingerprint
                                              ])
      )
      return existing if existing

      # Generate next sequential ID
      max_id = conn.select_value("SELECT MAX(id) FROM research_dataset_snapshots").to_i
      dataset_id = format("DS-%05d", max_id + 1)

      conn.execute(ActiveRecord::Base.sanitize_sql_array([
                                                           <<~SQL.squish,
                                                             INSERT INTO research_dataset_snapshots
                                                             (dataset_id, symbol, start_date, end_date, session_count, candle_count, fingerprint, status, created_at, updated_at)
                                                             VALUES (?, ?, ?, ?, ?, ?, ?, 'active', NOW(), NOW())
                                                           SQL
                                                           dataset_id, symbol, start_date.to_s, end_date.to_s, session_count, candle_count, fingerprint
                                                         ]))

      Rails.logger.info("[MROS::ExperimentRegistry] Created dataset snapshot #{dataset_id} — #{symbol} #{start_date}..#{end_date} (#{session_count} sessions)")
      dataset_id
    end

    # List all experiments, optionally filtered by verdict.
    # @param verdict [String, nil] "accepted", "rejected", or nil for all
    # @return [Array<Hash>]
    def self.list(verdict: nil)
      sql = "SELECT * FROM research_experiment_registry"
      sql += ActiveRecord::Base.sanitize_sql_array([" WHERE verdict = ?", verdict]) if verdict
      sql += " ORDER BY created_at DESC"

      ActiveRecord::Base.connection.select_all(sql).map(&:symbolize_keys)
    end

    def self.build_rejection_reason(evidence)
      reasons = []
      d = evidence[:details]
      reasons << "Insufficient sample size (#{d[:sample_size_score]}/100)" if d[:sample_size_score] < 40
      reasons << "Poor return stability (#{d[:return_stability_score]}/100)" if d[:return_stability_score] < 40
      reasons << "OOS replication failure (#{d[:oos_replication_score]}/100)" if d[:oos_replication_score] < 50
      reasons << "Low statistical confidence (#{d[:significance_confidence_score]}/100)" if d[:significance_confidence_score] < 50
      reasons.join("; ")
    end
    private_class_method :build_rejection_reason
  end
end
