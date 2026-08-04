# frozen_string_literal: true

module Research
  # Tracks every computed feature with versioned metadata, formula, and lifecycle.
  # Features are identified by a unique ID (F-001, F-002, ...) and can be
  # active or deprecated. Dependencies between features are stored for lineage.
  class FeatureRegistry
    FEATURE_CATALOGUE = {
      "F-001" => { name: "gap_pct", category: "auction", description: "Overnight gap as percentage of previous close", formula: "(open - prev_close) / prev_close * 100" },
      "F-002" => { name: "or_width", category: "auction", description: "Opening range width in points (15m high - 15m low)", formula: "high_15m - low_15m" },
      "F-003" => { name: "atr", category: "volatility", description: "14-period Average True Range", formula: "EMA(TR, 14)" },
      "F-004" => { name: "adx", category: "momentum", description: "14-period Average Directional Index", formula: "smoothed(+DI, -DI, 14)" },
      "F-005" => { name: "rsi", category: "momentum", description: "14-period Relative Strength Index", formula: "100 - (100 / (1 + avg_gain/avg_loss))" },
      "F-006" => { name: "vwap_dist", category: "liquidity", description: "Distance from VWAP as percentage", formula: "(price - vwap) / vwap * 100" },
      "F-007" => { name: "ignition_velocity", category: "auction", description: "Price velocity in first 3 minutes (pts/min)", formula: "nifty_move_3m / 3.0" },
      "F-008" => { name: "first_candle_body_ratio", category: "auction", description: "Body-to-range ratio of the first 1m candle", formula: "abs(close - open) / (high - low)" },
      "F-009" => { name: "first_candle_volume", category: "participation", description: "Volume of the first 1-minute candle", formula: "volume[0]" },
      "F-010" => { name: "gap_regime", category: "auction", description: "Classified gap bucket: gap_up, gap_down, flat_open", formula: "classify(gap_pct, thresholds)", dependencies: ["F-001"] },
      "F-011" => { name: "or_width_regime", category: "auction", description: "OR width bucket: narrow, moderate, wide", formula: "classify(or_width, thresholds)", dependencies: ["F-002"] },
      "F-012" => { name: "volatility_regime", category: "volatility", description: "ATR-based volatility regime: low, normal, high", formula: "classify(atr, percentiles)", dependencies: ["F-003"] },
      "F-013" => { name: "trend_regime", category: "momentum", description: "ADX-based trend regime: mean_reverting, neutral, trending", formula: "classify(adx, thresholds)", dependencies: ["F-004"] }
    }.freeze

    # Seed all known features into the database registry.
    # @return [Integer] Number of features registered
    def self.seed!
      conn = ActiveRecord::Base.connection
      count = 0

      FEATURE_CATALOGUE.each do |feature_id, meta|
        existing = conn.select_value(
          ActiveRecord::Base.sanitize_sql_array([
                                                  "SELECT COUNT(*) FROM research_feature_registry WHERE feature_id = ?", feature_id
                                                ])
        )
        next if existing.to_i.positive?

        conn.execute(ActiveRecord::Base.sanitize_sql_array([
                                                             <<~SQL.squish,
                                                               INSERT INTO research_feature_registry
                                                               (feature_id, name, category, description, formula, version, dependencies, status, introduced_on, created_at, updated_at)
                                                               VALUES (?, ?, ?, ?, ?, '1.0', ?, 'active', ?, NOW(), NOW())
                                                             SQL
                                                             feature_id,
                                                             meta[:name],
                                                             meta[:category],
                                                             meta[:description],
                                                             meta[:formula],
                                                             (meta[:dependencies] || []).to_json,
                                                             Date.current.to_s
                                                           ]))
        count += 1
      end

      Rails.logger.info("[MROS::FeatureRegistry] Seeded #{count} features into registry.")
      count
    end

    # Look up a feature by ID.
    # @param feature_id [String]
    # @return [Hash, nil]
    def self.lookup(feature_id)
      row = ActiveRecord::Base.connection.select_one(
        ActiveRecord::Base.sanitize_sql_array([
                                                "SELECT * FROM research_feature_registry WHERE feature_id = ?", feature_id
                                              ])
      )
      row&.symbolize_keys
    end

    # Deprecate a feature.
    # @param feature_id [String]
    def self.deprecate!(feature_id)
      ActiveRecord::Base.connection.execute(
        ActiveRecord::Base.sanitize_sql_array([
                                                <<~SQL.squish,
                                                  UPDATE research_feature_registry
                                                  SET status = 'deprecated', deprecated_on = ?, updated_at = NOW()
                                                  WHERE feature_id = ?
                                                SQL
                                                Date.current.to_s,
                                                feature_id
                                              ])
      )
    end
  end
end
