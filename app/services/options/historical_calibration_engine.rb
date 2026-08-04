# frozen_string_literal: true

require 'csv'

module Options
  # Offline calibration engine for options historical behaviour CSV output.
  # Pure Ruby: no DB/API dependency.
  class HistoricalCalibrationEngine
    DEFAULT_FEE_PER_ORDER = 20.0

    attr_reader :symbol, :rows, :fee_per_order

    def self.from_csv(csv_path:, symbol:, fee_per_order: DEFAULT_FEE_PER_ORDER)
      parsed_rows = CSV.read(csv_path, headers: true).map(&:to_h)
      filtered = parsed_rows.select { |r| r['symbol'].to_s.upcase == symbol.to_s.upcase }
      new(rows: filtered, symbol: symbol, fee_per_order: fee_per_order)
    end

    def initialize(rows:, symbol:, fee_per_order: DEFAULT_FEE_PER_ORDER)
      @rows = Array(rows)
      @symbol = symbol.to_s.upcase
      @fee_per_order = fee_per_order.to_f
    end

    def call
      ce = leg_summary('ce')
      pe = leg_summary('pe')

      combined = combined_summary(ce, pe)
      profiles = build_profiles(combined)
      objective = objective_summary(combined, profiles)
      confidence = confidence_level(combined)
      warnings = build_warnings(combined)

      {
        symbol: symbol,
        row_count: rows.size,
        ce: ce,
        pe: pe,
        combined: combined,
        objective: objective,
        profiles: profiles,
        confidence: confidence,
        warnings: warnings,
        suggested_patch: suggested_patch(profiles)
      }
    end

    private

    def leg_summary(prefix)
      gain = series("#{prefix}_max_gain_pct")
      loss_abs = series("#{prefix}_max_loss_pct").map(&:abs)
      retrace_abs = series("#{prefix}_retrace").map(&:abs)
      oc = series("#{prefix}_oc_pct")
      entry = series("#{prefix}_entry")
      corr = series("#{prefix}_corr_slope")

      session_map = {
        morning_oc: avg(series("#{prefix}_morning_oc")),
        midday_oc: avg(series("#{prefix}_midday_oc")),
        afternoon_oc: avg(series("#{prefix}_afternoon_oc"))
      }

      avg_entry = avg(entry)
      fee_pct = avg_entry.positive? ? ((fee_per_order * 2.0) / avg_entry * 100.0) : 0.0

      {
        avg_gain: avg(gain),
        avg_loss_abs: avg(loss_abs),
        avg_retrace_abs: avg(retrace_abs),
        avg_oc: avg(oc),
        oc_stddev: stddev(oc),
        avg_corr_slope: avg(corr),
        avg_entry: avg_entry,
        fee_pct: fee_pct,
        sessions: session_map
      }
    end

    def combined_summary(ce, pe)
      avg_gain = avg([ce[:avg_gain], pe[:avg_gain]])
      avg_loss_abs = avg([ce[:avg_loss_abs], pe[:avg_loss_abs]])
      avg_retrace_abs = avg([ce[:avg_retrace_abs], pe[:avg_retrace_abs]])
      avg_oc = avg([ce[:avg_oc], pe[:avg_oc]])
      fee_pct = avg([ce[:fee_pct], pe[:fee_pct]])
      avg_corr_slope = avg([ce[:avg_corr_slope], pe[:avg_corr_slope]])

      expectancy_after_fees = (avg_oc - fee_pct).round(2)
      drawdown_penalty = [avg_loss_abs - 10.0, 0.0].max * 0.6
      giveback_penalty = [avg_retrace_abs - 25.0, 0.0].max * 0.25
      stability_bonus = [10.0 - avg([ce[:oc_stddev], pe[:oc_stddev]]), 0.0].max * 0.2
      score = (expectancy_after_fees + stability_bonus - drawdown_penalty - giveback_penalty).round(2)

      {
        avg_gain: avg_gain,
        avg_loss_abs: avg_loss_abs,
        avg_retrace_abs: avg_retrace_abs,
        avg_oc: avg_oc,
        fee_pct: fee_pct,
        avg_corr_slope: avg_corr_slope,
        expectancy_after_fees: expectancy_after_fees,
        drawdown_penalty: drawdown_penalty.round(2),
        giveback_penalty: giveback_penalty.round(2),
        stability_bonus: stability_bonus.round(2),
        score: score,
        sessions: summarize_sessions(ce: ce, pe: pe)
      }
    end

    def summarize_sessions(ce:, pe:)
      {
        morning_oc: avg([ce.dig(:sessions, :morning_oc), pe.dig(:sessions, :morning_oc)]),
        midday_oc: avg([ce.dig(:sessions, :midday_oc), pe.dig(:sessions, :midday_oc)]),
        afternoon_oc: avg([ce.dig(:sessions, :afternoon_oc), pe.dig(:sessions, :afternoon_oc)])
      }
    end

    def build_profiles(combined)
      base_target = clamp((combined[:avg_gain] * 0.45) / 100.0, 0.08, 0.35)
      base_trail = clamp(1.0 - ((combined[:avg_retrace_abs] * 0.8) / 100.0), 0.55, 0.92)
      base_lock = clamp((combined[:avg_gain] * 0.20) / 100.0, 0.06, 0.15)

      weak_midday = combined.dig(:sessions, :midday_oc).to_f < 0.0
      weak_afternoon = combined.dig(:sessions, :afternoon_oc).to_f < 0.0

      time_stop = suggested_time_stop(symbol: symbol, weak_midday: weak_midday, weak_afternoon: weak_afternoon)

      {
        conservative: {
          target_pct: clamp(base_target * 0.85, 0.08, 0.35).round(3),
          trail_pct: clamp(base_trail + 0.05, 0.55, 0.92).round(3),
          lock_pct: clamp(base_lock + 0.02, 0.06, 0.15).round(3),
          time_stop_minutes: (time_stop * 0.8).round
        },
        balanced: {
          target_pct: base_target.round(3),
          trail_pct: base_trail.round(3),
          lock_pct: base_lock.round(3),
          time_stop_minutes: time_stop
        },
        aggressive: {
          target_pct: clamp(base_target * 1.15, 0.08, 0.35).round(3),
          trail_pct: clamp(base_trail - 0.05, 0.55, 0.92).round(3),
          lock_pct: clamp(base_lock - 0.02, 0.06, 0.15).round(3),
          time_stop_minutes: (time_stop * 1.2).round
        }
      }
    end

    def objective_summary(combined, profiles)
      {
        score: combined[:score],
        expectancy_after_fees_pct: combined[:expectancy_after_fees].round(2),
        penalties: {
          drawdown: combined[:drawdown_penalty],
          giveback: combined[:giveback_penalty]
        },
        bonus: {
          stability: combined[:stability_bonus]
        },
        recommended_profile: recommended_profile(profiles, combined)
      }
    end

    def recommended_profile(profiles, combined)
      return :conservative if combined[:score].negative?
      return :aggressive if combined[:score] > 8

      profiles[:balanced] ? :balanced : :conservative
    end

    def suggested_patch(profiles)
      balanced = profiles[:balanced]
      {
        risk: {
          percentage_pnl_exit: {
            enabled: true,
            target_pct: balanced[:target_pct]
          },
          profit_floor: {
            enabled: true,
            lock_pct: balanced[:lock_pct],
            trail_pct: balanced[:trail_pct]
          },
          time_stop: {
            enabled: true,
            trend: {
              symbol => balanced[:time_stop_minutes]
            }
          },
          institutional_trailing: {
            enabled: true,
            symbol.downcase.to_sym => {
              breakeven_trigger: clamp(balanced[:target_pct] * 0.4, 0.05, 0.20).round(3),
              activation_trigger: clamp(balanced[:target_pct] * 0.7, 0.10, 0.30).round(3),
              trailing_distance: clamp(1.0 - balanced[:trail_pct], 0.08, 0.45).round(3)
            }
          }
        }
      }
    end

    def confidence_level(combined)
      n = rows.size
      std = avg([combined[:avg_loss_abs], combined[:avg_retrace_abs]])

      return :low if n < 8
      return :medium if n < 20 || std > 40

      :high
    end

    def build_warnings(combined)
      warnings = []
      warnings << 'Low sample size (< 8 cycles) — treat suggestions as provisional.' if rows.size < 8
      warnings << 'High average retracement (> 60%) — tighten exits and validate aggressively.' if combined[:avg_retrace_abs] > 60
      if combined[:expectancy_after_fees].negative?
        warnings << 'Negative expectancy after fees — prefer conservative profile until refreshed data.'
      end
      warnings
    end

    def suggested_time_stop(symbol:, weak_midday:, weak_afternoon:)
      base = case symbol
             when 'NIFTY' then 20
             when 'SENSEX' then 10
             else 15
             end

      reduced = base
      reduced = (reduced * 0.8).round if weak_midday
      reduced = (reduced * 0.9).round if weak_afternoon
      [reduced, 6].max
    end

    def series(key)
      rows.filter_map { |r| float_or_nil(r[key]) }
    end

    def avg(values)
      arr = Array(values).compact
      return 0.0 if arr.empty?

      arr.sum / arr.size.to_f
    end

    def stddev(values)
      arr = Array(values).compact
      return 0.0 if arr.size < 2

      mean = avg(arr)
      variance = arr.sum { |v| (v - mean)**2 } / arr.size.to_f
      Math.sqrt(variance)
    end

    def clamp(value, min, max)
      [[value, min].max, max].min
    end

    def float_or_nil(value)
      return nil if value.nil?

      s = value.to_s.strip
      return nil if s.empty?

      Float(s)
    rescue ArgumentError
      nil
    end
  end
end
