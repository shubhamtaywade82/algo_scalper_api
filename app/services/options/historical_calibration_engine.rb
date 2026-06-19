# frozen_string_literal: true

module Options
  # Aggregates per-expiry-cycle calibration rows into CE/PE leg summaries.
  class HistoricalCalibrationEngine
    def initialize(rows:, symbol:)
      @rows = Array(rows)
      @symbol = symbol.to_s.upcase
    end

    def call
      ce = leg_summary('ce')
      pe = leg_summary('pe')
      combined = combine_legs(ce, pe)

      {
        symbol: @symbol,
        row_count: @rows.size,
        ce: ce,
        pe: pe,
        combined: combined
      }
    end

    private

    def leg_summary(prefix)
      gains = series("#{prefix}_max_gain_pct")
      losses = series("#{prefix}_max_loss_pct").map(&:abs)
      retraces = series("#{prefix}_retrace").map(&:abs)
      ocs = series("#{prefix}_oc_pct")

      {
        avg_gain: mean(gains),
        avg_loss_abs: mean(losses),
        avg_retrace_abs: mean(retraces),
        avg_oc: mean(ocs),
        oc_stddev: stddev(ocs),
        avg_entry: mean(series("#{prefix}_entry")),
        avg_corr_slope: mean(series("#{prefix}_corr_slope")),
        sessions: {
          morning_oc: mean(series("#{prefix}_morning_oc")),
          midday_oc: mean(series("#{prefix}_midday_oc")),
          afternoon_oc: mean(series("#{prefix}_afternoon_oc"))
        }
      }
    end

    def combine_legs(ce, pe)
      {
        avg_gain: average(ce[:avg_gain], pe[:avg_gain]),
        avg_loss_abs: average(ce[:avg_loss_abs], pe[:avg_loss_abs]),
        avg_retrace_abs: average(ce[:avg_retrace_abs], pe[:avg_retrace_abs]),
        avg_oc: average(ce[:avg_oc], pe[:avg_oc]),
        oc_stddev: average(ce[:oc_stddev], pe[:oc_stddev]),
        sessions: {
          morning_oc: average(ce.dig(:sessions, :morning_oc), pe.dig(:sessions, :morning_oc)),
          midday_oc: average(ce.dig(:sessions, :midday_oc), pe.dig(:sessions, :midday_oc)),
          afternoon_oc: average(ce.dig(:sessions, :afternoon_oc), pe.dig(:sessions, :afternoon_oc))
        }
      }
    end

    def series(key)
      @rows.map { |row| row[key] || row[key.to_sym] }.map(&:to_f)
    end

    def mean(values)
      return 0.0 if values.empty?

      (values.sum / values.size.to_f).round(4)
    end

    def stddev(values)
      return 0.0 if values.size < 2

      avg = values.sum / values.size.to_f
      variance = values.sum { |v| (v - avg)**2 } / values.size
      Math.sqrt(variance).round(4)
    end

    def average(a, b)
      ((a.to_f + b.to_f) / 2.0).round(4)
    end
  end
end
