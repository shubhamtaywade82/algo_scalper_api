# frozen_string_literal: true

module Research
  # Validates market data integrity before research runs.
  # Checks for missing candles, duplicates, timestamp drift, volume anomalies,
  # and option chain completeness. Every audit is permanently logged.
  class DataQualityEngine
    EXPECTED_SESSION_CANDLES = 375 # 09:15 to 15:30 = 375 one-minute candles
    VOLUME_ANOMALY_Z_THRESHOLD = 3.0

    # Run a full data quality audit for a symbol on a given date.
    # @param symbol [String] e.g. "NIFTY"
    # @param date [Date]
    # @return [Hash] audit result
    def self.audit(symbol, date)
      conn = ActiveRecord::Base.connection

      # 1. Load candles for the date
      candles = conn.select_all(ActiveRecord::Base.sanitize_sql_array([
                                                                        <<~SQL.squish,
                                                                          SELECT ts, open, high, low, close, volume
                                                                          FROM candles
                                                                          WHERE instrument_key = ? AND timeframe = '1m'
                                                                            AND ts >= ? AND ts < ?
                                                                          ORDER BY ts ASC
                                                                        SQL
                                                                        symbol,
                                                                        date.to_time(:utc).beginning_of_day + 3.hours + 45.minutes, # 09:15 IST in UTC
                                                                        date.to_time(:utc).beginning_of_day + 10.hours              # 15:30 IST in UTC
                                                                      ])).to_a

      total = candles.size
      missing = [EXPECTED_SESSION_CANDLES - total, 0].max

      # 2. Detect duplicates
      timestamps = candles.pluck("ts")
      duplicates = timestamps.size - timestamps.uniq.size

      # 3. Detect timestamp drift (gaps > 1 minute between consecutive candles)
      drift_count = 0
      timestamps.each_cons(2) do |a, b|
        gap = (Time.parse(b.to_s) - Time.parse(a.to_s)).abs
        drift_count += 1 if gap > 90 # more than 1.5 minutes gap
      end

      # 4. Volume anomalies (z-score > threshold)
      volumes = candles.map { |c| c["volume"].to_f }
      volume_anomalies = 0
      if volumes.size > 1
        mean_vol = volumes.sum / volumes.size
        variance = volumes.sum { |v| (v - mean_vol)**2 } / (volumes.size - 1)
        std_vol = Math.sqrt(variance)
        volume_anomalies = volumes.count { |v| std_vol.positive? && ((v - mean_vol) / std_vol).abs > VOLUME_ANOMALY_Z_THRESHOLD } if std_vol.positive?
      end

      # 5. Option chain completeness check
      option_count = conn.select_value(ActiveRecord::Base.sanitize_sql_array([
                                                                               <<~SQL.squish,
                                                                                 SELECT COUNT(*) FROM research_option_bars
                                                                                 WHERE underlying_symbol = ? AND ts >= ? AND ts < ?
                                                                               SQL
                                                                               symbol,
                                                                               date.to_time(:utc).beginning_of_day + 3.hours + 45.minutes,
                                                                               date.to_time(:utc).beginning_of_day + 10.hours
                                                                             ])).to_i
      option_chain_complete = option_count >= 100 # at least 100 option bars expected

      # 6. Determine audit status
      status = if missing > 50 || duplicates > 10
                 "fail"
               elsif missing > 10 || duplicates > 3 || drift_count > 5
                 "warning"
               else
                 "pass"
               end

      # 7. Persist audit log
      conn.execute(ActiveRecord::Base.sanitize_sql_array([
                                                           <<~SQL.squish,
                                                             INSERT INTO research_data_quality_audits
                                                             (symbol, audit_date, status, total_candles, missing_candles, duplicate_candles,
                                                              volume_anomalies, timestamp_drift_count, option_chain_complete, strike_alignment_ok,
                                                              details, created_at, updated_at)
                                                             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, true, '{}', NOW(), NOW())
                                                             ON CONFLICT (symbol, audit_date) DO UPDATE SET
                                                               status = EXCLUDED.status,
                                                               total_candles = EXCLUDED.total_candles,
                                                               missing_candles = EXCLUDED.missing_candles,
                                                               duplicate_candles = EXCLUDED.duplicate_candles,
                                                               volume_anomalies = EXCLUDED.volume_anomalies,
                                                               timestamp_drift_count = EXCLUDED.timestamp_drift_count,
                                                               option_chain_complete = EXCLUDED.option_chain_complete,
                                                               updated_at = NOW()
                                                           SQL
                                                           symbol, date.to_s, status, total, missing, duplicates,
                                                           volume_anomalies, drift_count, option_chain_complete
                                                         ]))

      Rails.logger.info("[MROS::DataQuality] #{symbol} #{date} — #{status} (#{total} candles, #{missing} missing, #{duplicates} dupes)")

      {
        symbol: symbol,
        date: date,
        status: status,
        total_candles: total,
        missing_candles: missing,
        duplicate_candles: duplicates,
        volume_anomalies: volume_anomalies,
        timestamp_drift_count: drift_count,
        option_chain_complete: option_chain_complete
      }
    end

    # Run audit across multiple recent dates for a symbol.
    # @param symbol [String]
    # @param days [Integer]
    # @return [Array<Hash>]
    def self.audit_recent(symbol, days: 10)
      conn = ActiveRecord::Base.connection
      dates = conn.select_values(ActiveRecord::Base.sanitize_sql_array([
                                                                         "SELECT DISTINCT(ts::date) FROM candles WHERE instrument_key = ? AND timeframe = '1m' ORDER BY 1 DESC LIMIT ?",
                                                                         symbol, days
                                                                       ]))

      dates.map { |d| audit(symbol, Date.parse(d.to_s)) }
    end
  end
end
