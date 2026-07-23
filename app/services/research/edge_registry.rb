# frozen_string_literal: true

module Research
  # Manages the lifecycle of accepted edges — from discovery through production to retirement.
  # Every edge is treated like a production model with portfolio-grade metadata:
  # expected return, win probability, drawdown, capacity, regime, and drift monitoring.
  #
  # Lifecycle: accepted → production → monitoring → degraded → retired
  class EdgeRegistry
    DRIFT_WARNING_THRESHOLD = 15.0  # percent
    DRIFT_RETIRE_THRESHOLD  = 30.0  # percent

    # Promote an accepted experiment to a production edge with portfolio metadata.
    # @param edge_id [String] e.g. "EDGE-001"
    # @param experiment_id [String] e.g. "EXP-00042"
    # @param description [String]
    # @param evidence_score [Integer]
    # @param confidence [Float]
    # @param regime [String] "bullish", "bearish", "neutral"
    # @param sample_size [Integer]
    # @param portfolio [Hash] optional portfolio properties
    # @return [String] edge_id
    def self.register(edge_id:, experiment_id:, description:, evidence_score:, confidence:, regime:, sample_size:, portfolio: {})
      conn = ActiveRecord::Base.connection
      conn.execute(ActiveRecord::Base.sanitize_sql_array([
                                                           <<~SQL.squish,
                                                             INSERT INTO research_edge_registry
                                                             (edge_id, experiment_id, description, evidence_score, confidence, regime,
                                                              sample_size, drift_pct, status, discovered_on, last_validated_on,
                                                              expected_return, win_probability, expected_drawdown, confidence_interval,
                                                              capacity, expiry_sensitivity, market,
                                                              created_at, updated_at)
                                                             VALUES (?, ?, ?, ?, ?, ?, ?, 0.0, 'accepted', ?, ?,
                                                                     ?, ?, ?, ?, ?, ?, ?,
                                                                     NOW(), NOW())
                                                             ON CONFLICT (edge_id) DO UPDATE SET
                                                               evidence_score = EXCLUDED.evidence_score,
                                                               confidence = EXCLUDED.confidence,
                                                               expected_return = EXCLUDED.expected_return,
                                                               win_probability = EXCLUDED.win_probability,
                                                               expected_drawdown = EXCLUDED.expected_drawdown,
                                                               confidence_interval = EXCLUDED.confidence_interval,
                                                               last_validated_on = EXCLUDED.last_validated_on,
                                                               updated_at = NOW()
                                                           SQL
                                                           edge_id, experiment_id, description, evidence_score, confidence,
                                                           regime, sample_size, Date.current.to_s, Date.current.to_s,
                                                           portfolio[:expected_return],
                                                           portfolio[:win_probability],
                                                           portfolio[:expected_drawdown],
                                                           portfolio[:confidence_interval],
                                                           portfolio[:capacity] || "unknown",
                                                           portfolio[:expiry_sensitivity],
                                                           portfolio[:market]
                                                         ]))

      Rails.logger.info("[MROS::EdgeRegistry] Registered #{edge_id} from #{experiment_id} — evidence: #{evidence_score}/100")
      edge_id
    end

    # Revalidate an edge and update its drift and status.
    # @param edge_id [String]
    # @param current_evidence_score [Integer] freshly computed evidence score
    # @return [Hash] { status:, drift_pct: }
    def self.revalidate(edge_id, current_evidence_score)
      conn = ActiveRecord::Base.connection
      row = conn.select_one(
        ActiveRecord::Base.sanitize_sql_array([
                                                "SELECT evidence_score, status FROM research_edge_registry WHERE edge_id = ?", edge_id
                                              ])
      )
      return { status: "not_found" } unless row

      original_score = row["evidence_score"].to_i
      drift = original_score.positive? ? ((original_score - current_evidence_score).to_f / original_score * 100.0).round(2) : 0.0

      new_status = if drift >= DRIFT_RETIRE_THRESHOLD
                     "retired"
                   elsif drift >= DRIFT_WARNING_THRESHOLD
                     "degraded"
                   elsif row["status"] == "retired"
                     "retired" # once retired, stay retired
                   else
                     row["status"]
                   end

      retirement_clause = new_status == "retired" ? ", retired_on = '#{Date.current}', retirement_reason = 'Drift exceeded #{DRIFT_RETIRE_THRESHOLD}%'" : ""

      conn.execute(ActiveRecord::Base.sanitize_sql_array([
                                                           "UPDATE research_edge_registry SET drift_pct = ?, status = ?, last_validated_on = ?#{retirement_clause}, updated_at = NOW() WHERE edge_id = ?",
                                                           drift, new_status, Date.current.to_s, edge_id
                                                         ]))

      Rails.logger.info("[MROS::EdgeRegistry] Revalidated #{edge_id} — drift: #{drift}%, status: #{new_status}")
      { status: new_status, drift_pct: drift }
    end

    # List all edges, optionally filtered by status.
    # @param status [String, nil]
    # @return [Array<Hash>]
    def self.list(status: nil)
      sql = "SELECT * FROM research_edge_registry"
      sql += ActiveRecord::Base.sanitize_sql_array([" WHERE status = ?", status]) if status
      sql += " ORDER BY evidence_score DESC"

      ActiveRecord::Base.connection.select_all(sql).map(&:symbolize_keys)
    end

    # List only production-ready edges that the execution engine should consume.
    # Returns portfolio-grade data: expected return, win probability, drawdown, etc.
    # @return [Array<Hash>]
    def self.production_edges
      ActiveRecord::Base.connection.select_all(
        <<~SQL.squish
          SELECT edge_id, experiment_id, description, evidence_score, confidence, regime,
                 sample_size, drift_pct, status, expected_return, win_probability,
                 expected_drawdown, confidence_interval, capacity, expiry_sensitivity, market,
                 discovered_on, last_validated_on
          FROM research_edge_registry
          WHERE status IN ('accepted', 'production') AND evidence_score >= 65
          ORDER BY evidence_score DESC
        SQL
      ).map(&:symbolize_keys)
    end
  end
end
