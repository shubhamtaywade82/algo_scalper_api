#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'base'
ServiceTestHelper.setup_rails

ServiceTestHelper.print_header('Signal::IndexSelector Service Test')

# Setup prerequisites
ServiceTestHelper.print_section('0. Prerequisites Setup')
ServiceTestHelper.setup_test_watchlist_items

# Test 1: Initialize IndexSelector
ServiceTestHelper.print_section('1. IndexSelector Initialization')
selector = Signal::IndexSelector.new(
  config: {
    min_trend_score: 15.0,
    primary_tf: '1m',
    confirmation_tf: '5m'
  }
)

ServiceTestHelper.print_info("IndexSelector initialized with min_trend_score: 15.0")

# Test 2: Select best index
ServiceTestHelper.print_section('2. Select Best Index')
best_index = selector.select_best_index

if best_index
  ServiceTestHelper.print_success("Best index selected: #{best_index[:index_key]}")
  ServiceTestHelper.print_info("  Trend score: #{best_index[:trend_score].round(2)}/21")
  ServiceTestHelper.print_info("  Reason: #{best_index[:reason]}")

  if best_index[:breakdown]
    ServiceTestHelper.print_info("  Breakdown:")
    ServiceTestHelper.print_info("    PA: #{best_index[:breakdown][:pa].round(2)}/7")
    ServiceTestHelper.print_info("    IND: #{best_index[:breakdown][:ind].round(2)}/7")
    ServiceTestHelper.print_info("    MTF: #{best_index[:breakdown][:mtf].round(2)}/7")
  end

  # Test 3: Check if score meets minimum threshold
  ServiceTestHelper.print_section('3. Minimum Threshold Check')
  if best_index[:trend_score] >= 15.0
    ServiceTestHelper.print_success("Trend score (#{best_index[:trend_score].round(2)}) meets minimum threshold (15.0)")
  else
    ServiceTestHelper.print_warning("Trend score (#{best_index[:trend_score].round(2)}) below minimum threshold (15.0)")
  end

  # Test 4: Test with different minimum thresholds
  ServiceTestHelper.print_section('4. Different Minimum Thresholds')
  [10.0, 15.0, 18.0].each do |min_score|
    selector_threshold = Signal::IndexSelector.new(
      config: { min_trend_score: min_score }
    )
    result = selector_threshold.select_best_index
    if result
      ServiceTestHelper.print_info("  min_trend_score=#{min_score}: Selected #{result[:index_key]} (score: #{result[:trend_score].round(2)})")
    else
      ServiceTestHelper.print_info("  min_trend_score=#{min_score}: No index qualified")
    end
  end
else
  ServiceTestHelper.print_warning("No index qualified (all below minimum trend score or error)")
end

# Test 5: Test with all configured indices
ServiceTestHelper.print_section('5. All Configured Indices')
indices = AlgoConfig.fetch[:indices] || []
ServiceTestHelper.print_info("Configured indices: #{indices.map { |idx| idx[:key] }.join(', ')}")

indices.each do |index_cfg|
  index_key = index_cfg[:key] || index_cfg['key']
  next unless index_key

  instrument = IndexInstrumentCache.instance.get_or_fetch(index_key: index_key.to_sym)
  next unless instrument

  scorer = Signal::TrendScorer.new(instrument: instrument, primary_tf: '1m', confirmation_tf: '5m')
  result = scorer.compute_trend_score

  if result && result[:trend_score]
    ServiceTestHelper.print_info("  #{index_key}: #{result[:trend_score].round(2)}/21")
  end
end

ServiceTestHelper.print_section('Summary')
ServiceTestHelper.print_info("IndexSelector test completed")
ServiceTestHelper.print_info("Use this service to select the best index for trading based on trend scores")

