#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'base'
ServiceTestHelper.setup_rails

ServiceTestHelper.print_header('Signal::TrendScorer Service Test')

# Setup prerequisites
ServiceTestHelper.print_section('0. Prerequisites Setup')
ServiceTestHelper.setup_test_watchlist_items

# Test 1: Initialize TrendScorer for NIFTY
ServiceTestHelper.print_section('1. TrendScorer Initialization')
indices = AlgoConfig.fetch[:indices] || []
nifty_index = indices.find { |idx| idx[:key] == 'NIFTY' || idx[:key] == :NIFTY }

if nifty_index
  nifty_instrument = IndexInstrumentCache.instance.get_or_fetch(index_key: :NIFTY)

  if nifty_instrument
    ServiceTestHelper.print_success("Found NIFTY instrument: #{nifty_instrument.symbol_name}")

    # Initialize TrendScorer
    scorer = Signal::TrendScorer.new(
      instrument: nifty_instrument,
      primary_tf: '1m',
      confirmation_tf: '5m'
    )

    ServiceTestHelper.print_info("TrendScorer initialized with primary_tf: 1m, confirmation_tf: 5m")

    # Test 2: Compute trend score
    ServiceTestHelper.print_section('2. Compute Trend Score')
    result = scorer.compute_trend_score

    if result && result[:trend_score]
      ServiceTestHelper.print_success("Trend score computed: #{result[:trend_score].round(2)}/21")
      ServiceTestHelper.print_info("  PA score: #{result[:breakdown][:pa].round(2)}/7")
      ServiceTestHelper.print_info("  IND score: #{result[:breakdown][:ind].round(2)}/7")
      ServiceTestHelper.print_info("  MTF score: #{result[:breakdown][:mtf].round(2)}/7")
      ServiceTestHelper.print_info("  VOL score: #{result[:breakdown][:vol].round(2)} (always 0 for indices)")

      # Test 3: Score interpretation
      ServiceTestHelper.print_section('3. Score Interpretation')
      trend_score = result[:trend_score]

      if trend_score >= 18
        ServiceTestHelper.print_success("Strong trend (>=18) - Allows 2OTM strikes")
      elsif trend_score >= 12
        ServiceTestHelper.print_info("Moderate trend (>=12) - Allows 1OTM strikes")
      elsif trend_score >= 7
        ServiceTestHelper.print_warning("Weak trend (>=7) - ATM only")
      else
        ServiceTestHelper.print_warning("Very weak trend (<7) - ATM only, low confidence")
      end

      # Test 4: Test with different timeframes
      ServiceTestHelper.print_section('4. Different Timeframe Configurations')
      ['1m', '5m', '15m'].each do |primary_tf|
        scorer_tf = Signal::TrendScorer.new(
          instrument: nifty_instrument,
          primary_tf: primary_tf,
          confirmation_tf: '5m'
        )
        result_tf = scorer_tf.compute_trend_score
        if result_tf && result_tf[:trend_score]
          ServiceTestHelper.print_info("  #{primary_tf} primary: #{result_tf[:trend_score].round(2)}/21")
        end
      end

      # Test 5: Error handling
      ServiceTestHelper.print_section('5. Error Handling')
      invalid_instrument = double('InvalidInstrument')
      scorer_invalid = Signal::TrendScorer.new(
        instrument: invalid_instrument,
        primary_tf: '1m'
      )
      result_invalid = scorer_invalid.compute_trend_score
      if result_invalid && result_invalid[:trend_score] == 0
        ServiceTestHelper.print_success("Gracefully handles invalid instrument (returns 0 score)")
      end
    else
      ServiceTestHelper.print_error("Failed to compute trend score")
    end
  else
    ServiceTestHelper.print_error("NIFTY instrument not found")
  end
else
  ServiceTestHelper.print_error("NIFTY index config not found in algo.yml")
end

ServiceTestHelper.print_section('Summary')
ServiceTestHelper.print_info("TrendScorer test completed")
ServiceTestHelper.print_info("Use this service to evaluate trend strength for index selection")

