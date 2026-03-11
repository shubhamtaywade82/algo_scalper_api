# frozen_string_literal: true

require 'yaml'
require_relative '../../app/services/options/historical_calibration_engine'

namespace :options do
  desc 'Generate risk/exit calibration suggestions from options:historical_behaviour CSV'
  # rubocop:disable Rails/RakeEnvironment
  task :calibrate_from_csv, [:csv_path, :symbol] do |_t, args|
    csv_path = args[:csv_path].to_s
    symbol = normalize_symbol(args[:symbol])
    validate_csv_path!(csv_path)

    engine = Options::HistoricalCalibrationEngine.from_csv(csv_path: csv_path, symbol: symbol)
    result = engine.call

    if result[:row_count].zero?
      puts "No rows found for symbol=#{symbol} in #{csv_path}"
      exit(1)
    end

    print_report(result, source: csv_path)
  end

  desc 'Run calibration across multiple CSV files and print median balanced profile suggestion'
  task :calibrate_batch, [:glob, :symbol] do |_t, args|
    glob = args[:glob].to_s
    symbol = normalize_symbol(args[:symbol])

    if glob.empty?
      puts "Usage: bundle exec rake 'options:calibrate_batch[/tmp/options_intraday_*.csv,SENSEX]'"
      exit(1)
    end

    files = Dir.glob(glob)
    if files.empty?
      puts "No CSV files matched: #{glob}"
      exit(1)
    end

    results = files.filter_map do |path|
      engine = Options::HistoricalCalibrationEngine.from_csv(csv_path: path, symbol: symbol)
      result = engine.call
      next if result[:row_count].zero?

      { path: path, result: result }
    end

    if results.empty?
      puts "No usable rows found for symbol=#{symbol} across matched files."
      exit(1)
    end

    puts "\n=== Batch Calibration Summary ==="
    puts "Symbol: #{symbol}"
    puts "Files considered: #{results.size}/#{files.size}"
    puts

    results.each do |entry|
      puts(
        "- #{entry[:path]} => score=#{entry[:result].dig(:objective, :score)} " \
        "profile=#{entry[:result].dig(:objective, :recommended_profile)}"
      )
    end

    median_patch = median_balanced_patch(extract(results, :result))
    puts "\nMedian balanced patch suggestion"
    puts yaml_from_hash(median_patch)
  end
  # rubocop:enable Rails/RakeEnvironment

  def print_report(result, source:)
    ce = result[:ce]
    pe = result[:pe]
    combined = result[:combined]
    objective = result[:objective]
    profiles = result[:profiles]

    puts "\n=== Options Calibration Recommendation ==="
    puts "Symbol: #{result[:symbol]}"
    puts "Rows: #{result[:row_count]}"
    puts "Source CSV: #{source}"
    puts

    puts "Computed Averages"
    puts "  CE avg max_gain_pct: #{fmt(ce[:avg_gain])}% | avg retrace: #{fmt(ce[:avg_retrace_abs])}% | avg max_loss: -#{fmt(ce[:avg_loss_abs])}% | avg OC: #{fmt(ce[:avg_oc])}%"
    puts "  PE avg max_gain_pct: #{fmt(pe[:avg_gain])}% | avg retrace: #{fmt(pe[:avg_retrace_abs])}% | avg max_loss: -#{fmt(pe[:avg_loss_abs])}% | avg OC: #{fmt(pe[:avg_oc])}%"
    puts

    puts "Objective Score Summary"
    puts "  Score: #{fmt(objective[:score])}"
    puts "  Expectancy after fees: #{fmt(objective[:expectancy_after_fees_pct])}%"
    puts "  Penalties => drawdown: #{fmt(objective.dig(:penalties, :drawdown))}, giveback: #{fmt(objective.dig(:penalties, :giveback))}"
    puts "  Bonus => stability: #{fmt(objective.dig(:bonus, :stability))}"
    puts "  Recommended profile: #{objective[:recommended_profile]}"
    puts

    puts "Recommended Profiles"
    profiles.each do |name, profile|
      puts(
        "  #{name}: target_pct=#{profile[:target_pct]}, trail_pct=#{profile[:trail_pct]}, " \
        "lock_pct=#{profile[:lock_pct]}, time_stop=#{profile[:time_stop_minutes]}m"
      )
    end
    puts

    puts "Suggested algo.yml patch"
    puts yaml_from_hash(result[:suggested_patch])

    puts "Confidence & Warnings"
    puts "  Confidence: #{result[:confidence]}"
    if result[:warnings].empty?
      puts '  Warnings: none'
    else
      result[:warnings].each { |warning| puts "  - #{warning}" }
    end

    puts "Session Snapshot (combined CE/PE)"
    puts "  Morning OC: #{fmt(combined.dig(:sessions, :morning_oc))}%"
    puts "  Midday OC: #{fmt(combined.dig(:sessions, :midday_oc))}%"
    puts "  Afternoon OC: #{fmt(combined.dig(:sessions, :afternoon_oc))}%"
  end

  def median_balanced_patch(results)
    balanced_profiles = results.map { |r| r.dig(:profiles, :balanced) }
    target = median(extract(balanced_profiles, :target_pct)).round(3)
    trail = median(extract(balanced_profiles, :trail_pct)).round(3)
    lock = median(extract(balanced_profiles, :lock_pct)).round(3)
    time_stop = median(extract(balanced_profiles, :time_stop_minutes)).round
    symbol = results.first[:symbol]

    {
      risk: {
        percentage_pnl_exit: { enabled: true, target_pct: target },
        profit_floor: { enabled: true, lock_pct: lock, trail_pct: trail },
        time_stop: { enabled: true, trend: { symbol => time_stop } }
      }
    }
  end

  def yaml_from_hash(hash)
    stringify_keys(hash).to_yaml(line_width: -1).delete_prefix("---\n")
  end

  def validate_csv_path!(csv_path)
    if csv_path.empty?
      puts "Usage: bundle exec rake 'options:calibrate_from_csv[/tmp/options_intraday_*.csv,SENSEX]'"
      exit(1)
    end

    return if File.exist?(csv_path)

    puts "CSV not found: #{csv_path}"
    exit(1)
  end

  def normalize_symbol(raw_symbol)
    symbol = raw_symbol.to_s.strip
    (symbol.empty? ? 'SENSEX' : symbol).upcase
  end

  def median(values)
    arr = Array(values).compact.sort
    return 0.0 if arr.empty?

    mid = arr.length / 2
    return arr[mid] if arr.length.odd?

    (arr[mid - 1] + arr[mid]) / 2.0
  end

  def fmt(value)
    format('%.2f', value.to_f)
  end

  # rubocop:disable Rails/Pluck
  def extract(collection, key)
    Array(collection).map { |item| item[key] }
  end
  # rubocop:enable Rails/Pluck

  def stringify_keys(value)
    case value
    when Hash
      value.each_with_object({}) { |(k, v), out| out[k.to_s] = stringify_keys(v) }
    when Array
      value.map { |v| stringify_keys(v) }
    else
      value
    end
  end
end
