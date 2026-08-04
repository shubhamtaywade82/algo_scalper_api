# frozen_string_literal: true

module Research
  class DataWarehouse
    # Initializes PostgreSQL database tables if they do not exist.
    # Uses ActiveRecord::Base.connection directly.
    def self.init_db
      conn = ActiveRecord::Base.connection

      # Safe V6 to V7 schema migration helper: drop old tables if event_uuid column is missing
      if conn.table_exists?(:research_events) && !conn.column_exists?(:research_events, :event_uuid)
        conn.execute("DROP TABLE IF EXISTS research_event_exits CASCADE;")
        conn.execute("DROP TABLE IF EXISTS research_event_strikes CASCADE;")
        conn.execute("DROP TABLE IF EXISTS research_events CASCADE;")
        conn.execute("DROP TABLE IF EXISTS research_feature_importances CASCADE;")
        conn.execute("DROP TABLE IF EXISTS research_hypotheses CASCADE;")
      end

      # 1. Create research_events table
      conn.execute(<<~SQL.squish)
        CREATE TABLE IF NOT EXISTS research_events (
          event_uuid VARCHAR(100) PRIMARY KEY,
          event_id VARCHAR(100),
          date DATE,
          event_type VARCHAR(50),
          breakout_type VARCHAR(50),
          entry_time TIMESTAMP,
          entry_index INTEGER,
          underlying_entry_price DOUBLE PRECISION,
          or_high DOUBLE PRECISION,
          or_low DOUBLE PRECISION,
          or_width DOUBLE PRECISION,
          max_continuation DOUBLE PRECISION,
          max_adverse DOUBLE PRECISION,
          sustained BOOLEAN,
          failed BOOLEAN,
          archetype VARCHAR(50),
          predicted_archetype VARCHAR(50),
          expected_opportunity_score INTEGER,
          gap_pct DOUBLE PRECISION,
          adx DOUBLE PRECISION,
          atr DOUBLE PRECISION,
          rsi DOUBLE PRECISION,
          vwap_dist DOUBLE PRECISION,
          volatility_regime VARCHAR(50),
          trend_regime VARCHAR(50),
          failure_reason VARCHAR(50),
          research_version VARCHAR(20),
          feature_version VARCHAR(20),
          indicator_version VARCHAR(20),
          exit_version VARCHAR(20),
          strategy_version VARCHAR(20),
          india_vix DOUBLE PRECISION,
          weekly_expiry BOOLEAN,
          monthly_expiry BOOLEAN,
          us_overnight_change DOUBLE PRECISION,
          sector_breadth DOUBLE PRECISION
        );
      SQL

      # 2. Create research_event_strikes table
      conn.execute(<<~SQL.squish)
        CREATE TABLE IF NOT EXISTS research_event_strikes (
          event_uuid VARCHAR(100),
          strike_label VARCHAR(50),
          entry_price DOUBLE PRECISION,
          peak_price DOUBLE PRECISION,
          mfe_pct DOUBLE PRECISION,
          mae_pct DOUBLE PRECISION,
          drawdown_from_peak_pct DOUBLE PRECISION,
          gamma_efficiency DOUBLE PRECISION,
          expansion_quality_score DOUBLE PRECISION,
          time_to_peak_minutes INTEGER,
          mfe_5m DOUBLE PRECISION,
          mfe_10m DOUBLE PRECISION,
          mfe_15m DOUBLE PRECISION,
          mfe_30m DOUBLE PRECISION,
          mfe_60m DOUBLE PRECISION,
          PRIMARY KEY (event_uuid, strike_label)
        );
      SQL

      # 3. Create research_event_exits table
      conn.execute(<<~SQL.squish)
        CREATE TABLE IF NOT EXISTS research_event_exits (
          event_uuid VARCHAR(100),
          strike_label VARCHAR(50),
          exit_strategy VARCHAR(50),
          exit_price DOUBLE PRECISION,
          exit_time TIMESTAMP,
          exit_reason VARCHAR(100),
          holding_time_minutes INTEGER,
          return_pct DOUBLE PRECISION,
          capture_efficiency DOUBLE PRECISION,
          opportunity_retention_ratio DOUBLE PRECISION,
          lost_profit_points DOUBLE PRECISION,
          leakage_time INTEGER,
          leakage_speed DOUBLE PRECISION,
          PRIMARY KEY (event_uuid, strike_label, exit_strategy)
        );
      SQL

      # 4. Create research_feature_importances table
      conn.execute(<<~SQL.squish)
        CREATE TABLE IF NOT EXISTS research_feature_importances (
          feature_name VARCHAR(100) PRIMARY KEY,
          pearson_correlation DOUBLE PRECISION,
          information_gain DOUBLE PRECISION
        );
      SQL

      # 5. Create research_hypotheses table
      conn.execute(<<~SQL.squish)
        CREATE TABLE IF NOT EXISTS research_hypotheses (
          description VARCHAR(255) PRIMARY KEY,
          sample_size INTEGER,
          success_rate DOUBLE PRECISION,
          expectancy_r DOUBLE PRECISION,
          verdict VARCHAR(50)
        );
      SQL
    end

    # Saves all events, strikes, exits, and features to the PostgreSQL research data warehouse.
    def self.save_run(trades, correlations, nonlinear_importance, hypotheses)
      init_db

      ActiveRecord::Base.transaction do
        conn = ActiveRecord::Base.connection

        # Clear prior features/hypotheses to avoid stale stats
        conn.execute("DELETE FROM research_feature_importances")
        conn.execute("DELETE FROM research_hypotheses")

        trades.each do |t|
          event_uuid = t[:event_uuid] || "#{t[:date].strftime('%Y%m%d')}-#{SecureRandom.hex(4)}"
          event_id = t[:event_id] || t[:date].to_s

          # Delete prior records for this event to simulate UPSERT safely and database-agnostically
          conn.execute(ActiveRecord::Base.sanitize_sql_array(["DELETE FROM research_event_exits WHERE event_uuid = ?", event_uuid]))
          conn.execute(ActiveRecord::Base.sanitize_sql_array(["DELETE FROM research_event_strikes WHERE event_uuid = ?", event_uuid]))
          conn.execute(ActiveRecord::Base.sanitize_sql_array(["DELETE FROM research_events WHERE event_uuid = ?", event_uuid]))

          # Context extraction
          ctx = t[:context] || {}

          # Insert Event
          conn.execute(ActiveRecord::Base.sanitize_sql_array([<<~SQL.squish,
            INSERT INTO research_events (
              event_uuid, event_id, date, event_type, breakout_type, entry_time, entry_index, underlying_entry_price,
              or_high, or_low, or_width, max_continuation, max_adverse, sustained, failed, archetype,
              predicted_archetype, expected_opportunity_score, gap_pct, adx, atr, rsi, vwap_dist,
              volatility_regime, trend_regime, failure_reason,
              research_version, feature_version, indicator_version, exit_version, strategy_version,
              india_vix, weekly_expiry, monthly_expiry, us_overnight_change, sector_breadth
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
          SQL
                                                              event_uuid,
                                                              event_id,
                                                              t[:date].to_s,
                                                              t[:event_type].to_s,
                                                              t[:breakout_type].to_s,
                                                              t[:entry_time],
                                                              t[:entry_index],
                                                              t[:underlying_entry_price],
                                                              t[:or_high],
                                                              t[:or_low],
                                                              t[:or_width],
                                                              t[:max_continuation],
                                                              t[:max_adverse],
                                                              t[:sustained],
                                                              t[:failed],
                                                              t[:archetype].to_s,
                                                              t[:predicted_archetype].to_s,
                                                              t[:expected_opportunity_score],
                                                              t[:gap_pct],
                                                              t[:adx],
                                                              t[:atr],
                                                              t[:rsi],
                                                              t[:vwap_dist],
                                                              t[:regime]&.[](:volatility).to_s,
                                                              t[:regime]&.[](:trend).to_s,
                                                              t[:failure_reason].to_s,
                                                              "V7.0", "V7.0", "V7.0", "V7.0", "V7.0",
                                                              ctx[:india_vix] || 14.5,
                                                              ctx[:weekly_expiry] || false,
                                                              ctx[:monthly_expiry] || false,
                                                              ctx[:us_overnight_change] || 0.0,
                                                              ctx[:sector_breadth] || 0.5]))

          t[:strikes].each do |label, str|
            # Insert Strike
            conn.execute(ActiveRecord::Base.sanitize_sql_array([<<~SQL.squish,
              INSERT INTO research_event_strikes (
                event_uuid, strike_label, entry_price, peak_price, mfe_pct, mae_pct, drawdown_from_peak_pct,
                gamma_efficiency, expansion_quality_score, time_to_peak_minutes,
                mfe_5m, mfe_10m, mfe_15m, mfe_30m, mfe_60m
              ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            SQL
                                                                event_uuid,
                                                                label,
                                                                str[:entry_price],
                                                                str[:peak_price],
                                                                str[:mfe_pct],
                                                                str[:mae_pct],
                                                                str[:drawdown_from_peak_pct],
                                                                str[:gamma_efficiency],
                                                                str[:expansion_quality_score],
                                                                str[:time_to_peak_minutes],
                                                                str[:horizons]&.[](:mfe_5m),
                                                                str[:horizons]&.[](:mfe_10m),
                                                                str[:horizons]&.[](:mfe_15m),
                                                                str[:horizons]&.[](:mfe_30m),
                                                                str[:horizons]&.[](:mfe_60m)]))

            str[:exits].each do |strategy_name, ext|
              # Insert Exit Simulation
              conn.execute(ActiveRecord::Base.sanitize_sql_array([<<~SQL.squish,
                INSERT INTO research_event_exits (
                  event_uuid, strike_label, exit_strategy, exit_price, exit_time, exit_reason,
                  holding_time_minutes, return_pct, capture_efficiency, opportunity_retention_ratio,
                  lost_profit_points, leakage_time, leakage_speed
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
              SQL
                                                                  event_uuid,
                                                                  label,
                                                                  strategy_name.to_s,
                                                                  ext[:exit_price],
                                                                  ext[:exit_time],
                                                                  ext[:exit_reason].to_s,
                                                                  ext[:holding_time_minutes],
                                                                  ext[:return_pct],
                                                                  ext[:capture_efficiency],
                                                                  ext[:opportunity_retention_ratio],
                                                                  ext[:lost_profit_points],
                                                                  ext[:leakage_time],
                                                                  ext[:leakage_speed]]))
            end
          end
        end

        # Save Feature Importance Gain and Correlations
        correlations.each do |feature_name, pearson|
          info_gain = nonlinear_importance&.[](:information_gains)&.[](feature_name) || 0.0
          conn.execute(ActiveRecord::Base.sanitize_sql_array([<<~SQL.squish, feature_name.to_s, pearson, info_gain]))
            INSERT INTO research_feature_importances (
              feature_name, pearson_correlation, information_gain
            ) VALUES (?, ?, ?)
          SQL
        end

        # Save Hypotheses
        hypotheses.each do |h|
          conn.execute(ActiveRecord::Base.sanitize_sql_array([<<~SQL.squish,
            INSERT INTO research_hypotheses (
              description, sample_size, success_rate, expectancy_r, verdict
            ) VALUES (?, ?, ?, ?, ?)
          SQL
                                                              h.description,
                                                              h.sample_size,
                                                              h.success_rate,
                                                              h.expectancy,
                                                              h.verdict.to_s]))
        end
      end
    end
  end
end
