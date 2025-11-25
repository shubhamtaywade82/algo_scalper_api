# frozen_string_literal: true

# Script to analyze ADX values for each index to set appropriate thresholds
# Usage: rails runner scripts/analyze_index_adx_values.rb

puts "\n" + "=" * 100
puts "INDEX ADX VALUE ANALYSIS - Setting Appropriate Thresholds"
puts "=" * 100 + "\n"

indices = AlgoConfig.fetch[:indices] || []
signals_cfg = AlgoConfig.fetch[:signals] || {}
supertrend_cfg = signals_cfg[:supertrend] || { period: 7, base_multiplier: 3.0 }
adx_cfg = signals_cfg[:adx] || {}

primary_tf = signals_cfg[:primary_timeframe] || '1m'
confirmation_tf = signals_cfg[:confirmation_timeframe] || '5m'

puts "Current Configuration:"
puts "  Primary Timeframe: #{primary_tf}"
puts "  Confirmation Timeframe: #{confirmation_tf}"
puts "  ADX Min Strength (1m): #{adx_cfg[:min_strength] || 'N/A'}"
puts "  ADX Confirmation Min Strength (5m): #{adx_cfg[:confirmation_min_strength] || 'N/A'}"
puts ""

results = {}

indices.each do |index_cfg|
  puts "📊 Analyzing #{index_cfg[:key]}"
  puts "-" * 100

  instrument = IndexInstrumentCache.instance.get_or_fetch(index_cfg)
  unless instrument
    puts "  ❌ Instrument not found"
    puts ""
    next
  end

  # Analyze both timeframes
  primary_analysis = Signal::Engine.analyze_timeframe(
    index_cfg: index_cfg,
    instrument: instrument,
    timeframe: primary_tf,
    supertrend_cfg: supertrend_cfg,
    adx_min_strength: 0 # No filter for analysis
  )

  confirmation_analysis = Signal::Engine.analyze_timeframe(
    index_cfg: index_cfg,
    instrument: instrument,
    timeframe: confirmation_tf,
    supertrend_cfg: supertrend_cfg,
    adx_min_strength: 0 # No filter for analysis
  )

  if primary_analysis[:status] == :ok
    primary_adx = primary_analysis[:adx_value]&.to_f || 0
    primary_trend = primary_analysis.dig(:supertrend, :trend)
    puts "  Primary (#{primary_tf}):"
    puts "    ADX: #{primary_adx.round(2)}"
    puts "    Trend: #{primary_trend}"
    puts "    Direction: #{primary_analysis[:direction]}"
  else
    puts "  Primary (#{primary_tf}): ❌ #{primary_analysis[:message]}"
    primary_adx = 0
  end

  if confirmation_analysis[:status] == :ok
    confirmation_adx = confirmation_analysis[:adx_value]&.to_f || 0
    confirmation_trend = confirmation_analysis.dig(:supertrend, :trend)
    puts "  Confirmation (#{confirmation_tf}):"
    puts "    ADX: #{confirmation_adx.round(2)}"
    puts "    Trend: #{confirmation_trend}"
    puts "    Direction: #{confirmation_analysis[:direction]}"
  else
    puts "  Confirmation (#{confirmation_tf}): ❌ #{confirmation_analysis[:message]}"
    confirmation_adx = 0
  end

  results[index_cfg[:key]] = {
    primary_adx: primary_adx,
    confirmation_adx: confirmation_adx,
    primary_trend: primary_trend,
    confirmation_trend: confirmation_trend
  }

  puts ""
end

# Calculate recommended thresholds
puts "📊 RECOMMENDED THRESHOLDS"
puts "-" * 100

# Get current thresholds
current_1m_threshold = adx_cfg[:min_strength] || 18
current_5m_threshold = adx_cfg[:confirmation_min_strength] || 20

puts "Current Thresholds:"
puts "  1m ADX: #{current_1m_threshold}"
puts "  5m ADX: #{current_5m_threshold}"
puts ""

# Calculate per-index recommendations
puts "Per-Index Recommendations:"
results.each do |index_key, data|
  primary_adx = data[:primary_adx]
  confirmation_adx = data[:confirmation_adx]

  # Recommended threshold is 70% of typical value (allows some margin)
  recommended_1m = (primary_adx * 0.7).round(1) if primary_adx.positive?
  recommended_5m = (confirmation_adx * 0.7).round(1) if confirmation_adx.positive?

  puts "#{index_key}:"
  puts "  Current 1m ADX: #{primary_adx.round(2)} → Recommended threshold: #{recommended_1m || 'N/A'}"
  puts "  Current 5m ADX: #{confirmation_adx.round(2)} → Recommended threshold: #{recommended_5m || 'N/A'}"

  # Check if current thresholds are too high
  if recommended_1m && current_1m_threshold > recommended_1m
    puts "    ⚠️  1m threshold (#{current_1m_threshold}) is too high! Should be <= #{recommended_1m}"
  end

  if recommended_5m && current_5m_threshold > recommended_5m
    puts "    ⚠️  5m threshold (#{current_5m_threshold}) is too high! Should be <= #{recommended_5m}"
  end

  puts ""
end

# Overall recommendation
puts "Overall Recommendation:"
all_primary_adx = results.values.map { |r| r[:primary_adx] }.select(&:positive?)
all_confirmation_adx = results.values.map { |r| r[:confirmation_adx] }.select(&:positive?)

if all_primary_adx.any?
  avg_primary = all_primary_adx.sum / all_primary_adx.size
  recommended_global_1m = (avg_primary * 0.7).round(1)
  puts "  Average 1m ADX: #{avg_primary.round(2)}"
  puts "  Recommended global 1m threshold: #{recommended_global_1m}"
end

if all_confirmation_adx.any?
  avg_confirmation = all_confirmation_adx.sum / all_confirmation_adx.size
  recommended_global_5m = (avg_confirmation * 0.7).round(1)
  puts "  Average 5m ADX: #{avg_confirmation.round(2)}"
  puts "  Recommended global 5m threshold: #{recommended_global_5m}"
end

puts ""
puts "=" * 100 + "\n"

