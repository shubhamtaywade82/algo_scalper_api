# frozen_string_literal: true

require 'csv'

namespace :options do
  desc 'Generate risk/exit calibration suggestions from options:historical_behaviour CSV'
  # rubocop:disable Rails/RakeEnvironment
  task :calibrate_from_csv, [:csv_path, :symbol] do |_t, args|
    csv_path = args[:csv_path].to_s
    symbol_arg = args[:symbol].to_s.strip
    symbol = (symbol_arg.empty? ? 'SENSEX' : symbol_arg).upcase

    if csv_path.blank?
      puts "Usage: bundle exec rake 'options:calibrate_from_csv[/tmp/options_intraday_*.csv,SENSEX]'"
      exit(1)
    end

    unless File.exist?(csv_path)
      puts "CSV not found: #{csv_path}"
      exit(1)
    end

    rows = CSV.read(csv_path, headers: true).select { |r| r['symbol'].to_s.upcase == symbol }
    if rows.empty?
      puts "No rows found for symbol=#{symbol} in #{csv_path}"
      exit(1)
    end

    ce = aggregate_leg(rows, prefix: 'ce')
    pe = aggregate_leg(rows, prefix: 'pe')

    ce_trail = suggested_trail_pct(ce[:avg_retrace_abs])
    pe_trail = suggested_trail_pct(pe[:avg_retrace_abs])
    trail_pct = avg([ce_trail, pe_trail]).round(3)

    ce_target = suggested_target_pct(ce[:avg_gain])
    pe_target = suggested_target_pct(pe[:avg_gain])
    target_pct = avg([ce_target, pe_target]).round(3)

    ce_be = suggested_breakeven_gain_pct(ce[:avg_gain])
    pe_be = suggested_breakeven_gain_pct(pe[:avg_gain])
    be_gain_pct = avg([ce_be, pe_be]).round(2)

    puts "\n=== Options Calibration Recommendation ==="
    puts "Symbol: #{symbol}"
    puts "Rows: #{rows.size}"
    puts "Source CSV: #{csv_path}"
    puts
    puts "Computed Averages"
    puts "  CE avg max_gain_pct: #{fmt(ce[:avg_gain])}% | avg retrace: #{fmt(ce[:avg_retrace_abs])}% | avg max_loss: -#{fmt(ce[:avg_loss_abs])}%"
    puts "  PE avg max_gain_pct: #{fmt(pe[:avg_gain])}% | avg retrace: #{fmt(pe[:avg_retrace_abs])}% | avg max_loss: -#{fmt(pe[:avg_loss_abs])}%"
    puts
    puts "Suggested algo.yml patch"
    puts <<~YAML
      risk:
        percentage_pnl_exit:
          enabled: true
          target_pct: #{target_pct}   # derived from historical ATM max-gain behaviour
        profit_floor:
          enabled: true
          trail_pct: #{trail_pct}     # derived from post-peak retracement (tighter when retrace is high)
        # Breakeven guidance (gain-based):
        # Arm breakeven around +#{be_gain_pct}% option premium gain.
    YAML

    puts "Notes"
    puts "  1. Re-run monthly: behaviour shifts near volatility regime changes."
    puts "  2. Validate in exit_testing before production profile."
    puts "  3. If live gives back too much from HWM, reduce trail_pct by 0.03-0.05."
  end
  # rubocop:enable Rails/RakeEnvironment

  def aggregate_leg(rows, prefix:)
    gain_values = rows.filter_map { |r| float_or_nil(r["#{prefix}_max_gain_pct"]) }
    retrace_values = rows.filter_map { |r| float_or_nil(r["#{prefix}_retrace"])&.abs }
    loss_values = rows.filter_map { |r| float_or_nil(r["#{prefix}_max_loss_pct"])&.abs }

    {
      avg_gain: avg(gain_values),
      avg_retrace_abs: avg(retrace_values),
      avg_loss_abs: avg(loss_values)
    }
  end

  def suggested_trail_pct(avg_retrace_abs_pct)
    retrace = avg_retrace_abs_pct.to_f
    # Keep ~80% of typical retrace room from HWM.
    # Example: retrace 30% => floor retains ~76% of HWM.
    value = 1.0 - ((retrace * 0.8) / 100.0)
    clamp(value, 0.55, 0.92)
  end

  def suggested_target_pct(avg_gain_pct)
    gain = avg_gain_pct.to_f
    value = (gain * 0.45) / 100.0
    clamp(value, 0.08, 0.35)
  end

  def suggested_breakeven_gain_pct(avg_gain_pct)
    gain = avg_gain_pct.to_f
    clamp(gain * 0.25, 2.0, 15.0)
  end

  def avg(values)
    arr = Array(values).compact
    return 0.0 if arr.empty?

    arr.sum / arr.size.to_f
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

  def fmt(value)
    format('%.2f', value.to_f)
  end
end
