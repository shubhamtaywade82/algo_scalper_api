# frozen_string_literal: true

# rubocop:disable RSpec/MultipleExpectations
# rubocop:disable RSpec/ExampleLength

require "rails_helper"

RSpec.describe Research::First15mEngine do
  let(:base_time) { Time.zone.parse("2026-07-10 09:15:00") }

  # Construct synthetic underlying NIFTY 1m candles for a single day
  def mock_nifty_candles(start_price:, trend_direction: :flat, step_change: 0.0)
    price = start_price
    Array.new(375) do |i|
      timestamp = base_time + i.minutes
      c_open = price
      c_close = case trend_direction
                when :up then price + step_change
                when :down then price - step_change
                else price + (i.even? ? 1.0 : -1.0)
                end
      c_high = [c_open, c_close].max + 0.5
      c_low = [c_open, c_close].min - 0.5
      price = c_close

      {
        timestamp: timestamp,
        open: c_open,
        high: c_high,
        low: c_low,
        close: c_close,
        volume: 1000 + i
      }
    end
  end

  describe Research::AuctionArchetypeClassifier do
    it "correctly classifies day into an auction archetype" do
      nifty_candles = mock_nifty_candles(start_price: 25_000.0, trend_direction: :flat)
      day_data = {
        gap_pct: 0.05,
        days_to_expiry: 4,
        underlying_candles: nifty_candles,
        atr: 20.0
      }

      archetype = described_class.classify(day_data)
      expect(archetype).to eq(:open_auction)
    end
  end

  describe Research::EventSegmenter do
    let(:nifty_candles) { mock_nifty_candles(start_price: 25_000.0, trend_direction: :up, step_change: 0.5) }

    it "segments daily candles into multiple events" do
      day_data = {
        date: base_time.to_date,
        gap_pct: 0.15,
        days_to_expiry: 4,
        underlying_candles: nifty_candles,
        atr: 20.0,
        adx: 25.0,
        rsi: 55.0,
        vwap: 25_000.0,
        vwap_dist: 2.0
      }

      events = described_class.segment(day_data, target_points: 50.0)
      expect(events).to be_an(Array)
      expect(events.first[:event_type]).to eq(:bullish_breakout)
    end
  end

  describe Research::NonlinearFeatureImportance do
    it "computes Mutual Information and binned conditional probabilities" do
      mock_trades = [
        { gap_pct: 0.1, or_width: 20.0, atr: 10.0, adx: 10.0, rsi: 50.0, vwap_dist: 2.0, strikes: { "ATM" => { mfe_pct: 15.0 } } },
        { gap_pct: 0.5, or_width: 40.0, atr: 20.0, adx: 35.0, rsi: 60.0, vwap_dist: 5.0, strikes: { "ATM" => { mfe_pct: 45.0 } } },
        { gap_pct: -0.2, or_width: 30.0, atr: 15.0, adx: 25.0, rsi: 45.0, vwap_dist: 3.0, strikes: { "ATM" => { mfe_pct: 20.0 } } }
      ]

      result = described_class.analyze(mock_trades, strike_label: "ATM")
      expect(result[:information_gains]).to have_key(:gap_regime)
      expect(result[:conditional_probability_tables][:gap_regime]).to be_a(Hash)
    end
  end

  describe Research::OpportunityScorer do
    it "correctly calculates Expected Opportunity Score (EOS)" do
      expansion_ctx = {
        mfe_pct: 65.0,
        mae_pct: -5.0,
        drawdown_from_peak_pct: 10.0
      }

      eos = described_class.score(expansion_ctx)
      expect(eos).to be_between(0, 100)
    end
  end

  describe Research::RegimeClassifier do
    it "correctly classifies volatility, expiry, and trend regimes" do
      opp = {
        gap_pct: 0.55,
        days_to_expiry: 1,
        prev_day_close: 25_000.0,
        prev_day_high: 25_030.0,
        prev_day_low: 24_970.0,
        atr: 300.0,
        underlying_candles: [
          { open: 25_000.0 }
        ]
      }

      regime = described_class.classify(opp)
      expect(regime[:volatility]).to eq(:high_volatility)
      expect(regime[:expiry]).to eq(:near_expiry)
      expect(regime[:gap]).to eq(:large_gap)
      expect(regime[:trend]).to eq(:mean_reverting)
    end
  end

  describe Research::LifecyclePhases do
    let(:nifty_candles) { mock_nifty_candles(start_price: 25_000.0, trend_direction: :up, step_change: 0.5) }
    let(:ce_candles) { Research::MarketDataFetcher.simulate_option_premium("CE", 25_000.0, nifty_candles) }

    it "correctly traces start/end times and durations for all 7 option lifecycle phases" do
      day_data = { date: base_time.to_date, underlying_candles: nifty_candles }
      opps = Research::OpeningRangeAnalyzer.analyze(day_data, range_minutes: 15)
      opp = opps.first
      expansion_ctx = Research::OptionExpansionAnalyzer.analyze(ce_candles, nifty_candles, opp, "ATM")

      phases = described_class.trace(ce_candles, nifty_candles, opp, expansion_ctx)
      expect(phases).to have_key(:compression)
      expect(phases).to have_key(:auction)
      expect(phases).to have_key(:ignition)
      expect(phases).to have_key(:expansion)
      expect(phases).to have_key(:momentum_decay)
      expect(phases).to have_key(:exhaustion)
      expect(phases).to have_key(:distribution)
    end
  end

  describe Research::NegativeResearch do
    let(:nifty_candles) { mock_nifty_candles(start_price: 25_000.0, trend_direction: :up, step_change: 1.0) }
    let(:ce_candles) { Research::MarketDataFetcher.simulate_option_premium("CE", 25_000.0, nifty_candles) }

    it "correctly attributes breakout failures to specific failure reasons" do
      opp = {
        failed: true,
        entry_time: base_time + 16.minutes,
        entry_index: 16,
        breakout_type: :bullish,
        max_continuation: 5.0,
        prev_day_close: 25_000.0
      }
      regime = { trend: :mean_reverting }
      expansion_ctx = {
        time_to_peak_minutes: 10,
        exhaustion: { peak_exhaustion_score: 30, divergence_detected: false }
      }

      reason = described_class.analyze(nifty_candles, ce_candles, opp, expansion_ctx, regime)
      expect(reason).to eq(:mean_reverting_regime)
    end
  end

  describe Research::FeatureImportance do
    it "computes Pearson Correlation Coefficients between feature matrices and MFE" do
      mock_trades = [
        { gap_pct: 0.1, or_width: 20.0, atr: 10.0, adx: 20.0, rsi: 50.0, vwap_dist: 2.0, first_candle_body_ratio: 0.5, first_candle_volume: 1000, ignition: { ignition_velocity: 1.0 }, strikes: { "ATM" => { mfe_pct: 15.0 } } },
        { gap_pct: 0.5, or_width: 40.0, atr: 20.0, adx: 30.0, rsi: 60.0, vwap_dist: 5.0, first_candle_body_ratio: 0.8, first_candle_volume: 5000, ignition: { ignition_velocity: 5.0 }, strikes: { "ATM" => { mfe_pct: 45.0 } } }
      ]

      correlations = described_class.analyze(mock_trades, strike_label: "ATM")
      expect(correlations[:gap_pct]).to be_within(0.01).of(1.0) # perfect positive correlation in this mock
      expect(correlations[:first_candle_volume]).to be_within(0.01).of(1.0)
    end
  end

  describe Research::StatisticalValidator do
    it "computes bootstrapped confidence intervals and Walk-Forward In-Sample vs Out-of-Sample metrics" do
      mock_trades = [
        { entry_time: base_time, strikes: { "ATM" => { exits: { hybrid_divergence: { return_pct: 10.0, capture_efficiency: 0.5 }, trail_20: { return_pct: -5.0, capture_efficiency: 0.0 } } } } },
        { entry_time: base_time + 1.day, strikes: { "ATM" => { exits: { hybrid_divergence: { return_pct: 20.0, capture_efficiency: 0.6 }, trail_20: { return_pct: -5.0, capture_efficiency: 0.0 } } } } },
        { entry_time: base_time + 2.days, strikes: { "ATM" => { exits: { hybrid_divergence: { return_pct: 15.0, capture_efficiency: 0.55 }, trail_20: { return_pct: 25.0, capture_efficiency: 0.7 } } } } }
      ]

      val = described_class.run(mock_trades, strike_label: "ATM", iterations: 100)
      expect(val[:hybrid_divergence][:bootstrap][:expected_return_95_ci]).to be_an(Array)
      expect(val[:hybrid_divergence][:split_validation][:is_avg_return_pct]).to be_a(Numeric)
      expect(val[:hybrid_divergence][:split_validation][:oos_avg_return_pct]).to be_a(Numeric)
    end
  end

  describe Research::ResearchReportGenerator do
    it "correctly aggregates V5 metrics and outputs CSV/JSON reports" do
      mock_trade = {
        date: base_time.to_date,
        breakout_type: :bullish,
        entry_time: base_time + 16.minutes,
        underlying_entry_price: 25_008.0,
        or_high: 25_000.0,
        or_low: 24_980.0,
        or_width: 20.0,
        gap_pct: 0.25,
        is_inside_day: false,
        is_outside_day: true,
        relation_to_pdh_pdl: :above_pdh,
        days_to_expiry: 4,
        day_of_week: "Thursday",
        max_continuation: 60.0,
        max_adverse: 10.0,
        sustained: true,
        failed: false,
        atr: 12.0,
        adx: 25.0,
        rsi: 62.0,
        vwap: 25_000.0,
        vwap_dist: 8.0,
        first_candle_body_ratio: 0.65,
        first_candle_volume: 50_000,
        expected_opportunity_score: 78,
        archetype: :open_auction,
        regime: { volatility: :high_volatility, trend: :trending },
        lifecycle_phases: { compression: { duration_mins: 0 }, auction: { duration_mins: 15 }, ignition: { duration_mins: 3 }, expansion: { duration_mins: 20 }, momentum_decay: { duration_mins: 10 }, exhaustion: { duration_mins: 5 }, distribution: { duration_mins: 300 } },
        failure_reason: :none,
        strikes: {
          "ATM-2" => { mfe_pct: 80.0, mae_pct: -5.0, drawdown_from_peak_pct: 10.0, trade_elasticity: 2.0, gamma_efficiency: 1.6, expansion_quality_score: 85, entry_price: 200.0, peak_price: 360.0, time_to_peak_minutes: 20, peak_time: base_time + 30.minutes, exhaustion: { peak_exhaustion_score: 40.0, exhaustion_time: nil, divergence_detected: false }, thresholds: { time_to_50: nil, time_above_50: nil }, horizons: { mfe_5m: 10.0, mfe_10m: 15.0, mfe_15m: 20.0, mfe_30m: 25.0, mfe_60m: 30.0 }, exits: { hybrid_divergence: { return_pct: 70.0, capture_efficiency: 0.87, opportunity_retention_ratio: 0.87, lost_profit_points: 10.0, leakage_time: 5, leakage_speed: 2.0 }, trail_20: { return_pct: 60.0, capture_efficiency: 0.75, opportunity_retention_ratio: 0.75, lost_profit_points: 20.0, leakage_time: 5, leakage_speed: 4.0 }, momentum_decay: { return_pct: 65.0, capture_efficiency: 0.81, opportunity_retention_ratio: 0.81, lost_profit_points: 15.0, leakage_time: 5, leakage_speed: 3.0 } } },
          "ATM-1" => { mfe_pct: 70.0, mae_pct: -5.0, drawdown_from_peak_pct: 10.0, trade_elasticity: 1.8, gamma_efficiency: 1.4, expansion_quality_score: 80, entry_price: 150.0, peak_price: 255.0, time_to_peak_minutes: 20, peak_time: base_time + 30.minutes, exhaustion: { peak_exhaustion_score: 40.0, exhaustion_time: nil, divergence_detected: false }, thresholds: { time_to_50: nil, time_above_50: nil }, horizons: { mfe_5m: 10.0, mfe_10m: 15.0, mfe_15m: 20.0, mfe_30m: 25.0, mfe_60m: 30.0 }, exits: { hybrid_divergence: { return_pct: 60.0, capture_efficiency: 0.85, opportunity_retention_ratio: 0.85, lost_profit_points: 10.0, leakage_time: 5, leakage_speed: 2.0 }, trail_20: { return_pct: 50.0, capture_efficiency: 0.71, opportunity_retention_ratio: 0.71, lost_profit_points: 20.0, leakage_time: 5, leakage_speed: 4.0 }, momentum_decay: { return_pct: 55.0, capture_efficiency: 0.78, opportunity_retention_ratio: 0.78, lost_profit_points: 15.0, leakage_time: 5, leakage_speed: 3.0 } } },
          "ATM" => { mfe_pct: 60.0, mae_pct: -5.0, drawdown_from_peak_pct: 10.0, trade_elasticity: 1.5, gamma_efficiency: 1.2, expansion_quality_score: 75, entry_price: 100.0, peak_price: 160.0, time_to_peak_minutes: 20, peak_time: base_time + 30.minutes, exhaustion: { peak_exhaustion_score: 40.0, exhaustion_time: nil, divergence_detected: false }, thresholds: { time_to_50: nil, time_above_50: nil }, horizons: { mfe_5m: 10.0, mfe_10m: 15.0, mfe_15m: 20.0, mfe_30m: 25.0, mfe_60m: 30.0 }, exits: {
            fixed_30: { return_pct: 30.0, capture_efficiency: 0.50, opportunity_retention_ratio: 0.50, lost_profit_points: 30.0, leakage_time: 5, leakage_speed: 6.0, holding_time_minutes: 10 },
            fixed_50: { return_pct: 50.0, capture_efficiency: 0.83, opportunity_retention_ratio: 0.83, lost_profit_points: 10.0, leakage_time: 5, leakage_speed: 2.0, holding_time_minutes: 15 },
            trail_20: { return_pct: 48.0, capture_efficiency: 0.80, opportunity_retention_ratio: 0.80, lost_profit_points: 12.0, leakage_time: 5, leakage_speed: 2.4, holding_time_minutes: 18 },
            und_ema9: { return_pct: 40.0, capture_efficiency: 0.66, opportunity_retention_ratio: 0.66, lost_profit_points: 20.0, leakage_time: 5, leakage_speed: 4.0, holding_time_minutes: 22 },
            prem_ema5: { return_pct: 42.0, capture_efficiency: 0.70, opportunity_retention_ratio: 0.70, lost_profit_points: 18.0, leakage_time: 5, leakage_speed: 3.6, holding_time_minutes: 20 },
            momentum_decay: { return_pct: 45.0, capture_efficiency: 0.75, opportunity_retention_ratio: 0.75, lost_profit_points: 15.0, leakage_time: 5, leakage_speed: 3.0, holding_time_minutes: 19 },
            hybrid_divergence: { return_pct: 50.0, capture_efficiency: 0.83, opportunity_retention_ratio: 0.83, lost_profit_points: 10.0, leakage_time: 5, leakage_speed: 2.0, holding_time_minutes: 19 },
            hold_to_close: { return_pct: 20.0, capture_efficiency: 0.33, opportunity_retention_ratio: 0.33, lost_profit_points: 40.0, leakage_time: 5, leakage_speed: 8.0, holding_time_minutes: 360 }
          } },
          "ATM+1" => { mfe_pct: 50.0, mae_pct: -5.0, drawdown_from_peak_pct: 10.0, trade_elasticity: 1.2, gamma_efficiency: 1.0, expansion_quality_score: 70, entry_price: 60.0, peak_price: 90.0, time_to_peak_minutes: 20, peak_time: base_time + 30.minutes, exhaustion: { peak_exhaustion_score: 40.0, exhaustion_time: nil, divergence_detected: false }, thresholds: { time_to_50: nil, time_above_50: nil }, horizons: { mfe_5m: 10.0, mfe_10m: 15.0, mfe_15m: 20.0, mfe_30m: 25.0, mfe_60m: 30.0 }, exits: { hybrid_divergence: { return_pct: 40.0, capture_efficiency: 0.80, opportunity_retention_ratio: 0.80, lost_profit_points: 10.0, leakage_time: 5, leakage_speed: 2.0 }, trail_20: { return_pct: 30.0, capture_efficiency: 0.60, opportunity_retention_ratio: 0.60, lost_profit_points: 20.0, leakage_time: 5, leakage_speed: 4.0 }, momentum_decay: { return_pct: 35.0, capture_efficiency: 0.70, opportunity_retention_ratio: 0.70, lost_profit_points: 15.0, leakage_time: 5, leakage_speed: 3.0 } } },
          "ATM+2" => { mfe_pct: 40.0, mae_pct: -5.0, drawdown_from_peak_pct: 10.0, trade_elasticity: 1.0, gamma_efficiency: 0.8, expansion_quality_score: 65, entry_price: 30.0, peak_price: 42.0, time_to_peak_minutes: 20, peak_time: base_time + 30.minutes, exhaustion: { peak_exhaustion_score: 40.0, exhaustion_time: nil, divergence_detected: false }, thresholds: { time_to_50: nil, time_above_50: nil }, horizons: { mfe_5m: 10.0, mfe_10m: 15.0, mfe_15m: 20.0, mfe_30m: 25.0, mfe_60m: 30.0 }, exits: { hybrid_divergence: { return_pct: 30.0, capture_efficiency: 0.75, opportunity_retention_ratio: 0.75, lost_profit_points: 10.0, leakage_time: 5, leakage_speed: 2.0 }, trail_20: { return_pct: 20.0, capture_efficiency: 0.50, opportunity_retention_ratio: 0.50, lost_profit_points: 20.0, leakage_time: 5, leakage_speed: 4.0 }, momentum_decay: { return_pct: 25.0, capture_efficiency: 0.62, opportunity_retention_ratio: 0.62, lost_profit_points: 15.0, leakage_time: 5, leakage_speed: 3.0 } } }
        }
      }

      correlations = { gap_pct: 0.8 }
      val_reports = {
        fixed_30: { bootstrap: { expected_return_95_ci: [25.0, 35.0] }, split_validation: { is_avg_return_pct: 30.0, oos_avg_return_pct: 28.0 } }
      }
      negative_analysis = { vwap_reclaimed: 1 }
      nonlinear_importance = { information_gains: { gap_regime: 0.15 }, conditional_probability_tables: { gap_regime: { flat_open: { sample: 1, probability_pct: 100.0 } } } }
      archetype_analysis = { open_auction: 1 }

      report = described_class.run(
        [mock_trade],
        correlations: correlations,
        nonlinear_importance: nonlinear_importance,
        validation_reports: val_reports,
        negative_analysis: negative_analysis,
        archetype_analysis: archetype_analysis,
        output_dir: "tmp/test_research"
      )

      expect(report[:total_trade_opportunities]).to eq(1)
      expect(report[:feature_importance][:gap_pct]).to eq(0.8)
    end
  end

  describe Research::EdgeScorer do
    it "computes a probabilistic Edge Score based on returns, reliability, and sample size" do
      returns = [40.0, 45.0, 50.0, 35.0, 60.0]
      score = described_class.score(returns, 30.0)
      expect(score).to be_an(Integer)
      expect(score).to be > 0
    end
  end

  describe Research::HypothesisEngine do
    it "computes binomial p-values and applies Benjamini-Hochberg FDR correction" do
      mock_trades = [
        { breakout_type: :bullish, is_inside_day: true, or_width: 20.0, adx: 25.0, sustained: true, strikes: { "ATM" => { mfe_pct: 40.0 } } },
        { breakout_type: :bullish, is_inside_day: true, or_width: 20.0, adx: 25.0, sustained: true, strikes: { "ATM" => { mfe_pct: 40.0 } } }
      ]

      hyps = described_class.run(mock_trades)
      compression_hyp = hyps.find { |h| h.description.include?("Inside Day") }
      expect(compression_hyp).not_to be_nil
      expect(compression_hyp.sample_size).to eq(2)
      expect(compression_hyp.success_rate).to eq(100.0)
      expect(compression_hyp.p_value).to be_within(0.01).of(0.25)
      expect(compression_hyp.verdict).to eq(:needs_more_samples)
      expect(compression_hyp.reason).to include("below the expected minimum of 250")
    end

    it "sets verdict to insufficient_evidence when sample size is 0" do
      hyps = described_class.run([])
      hyps.each do |h|
        expect(h.verdict).to eq(:insufficient_evidence)
        expect(h.reason).to eq("No matching sample events found")
      end
    end

    it "correctly classifies as accepted when sample size >= 250 and statistical/performance requirements are met" do
      mock_trades = Array.new(250) do
        {
          breakout_type: :bullish,
          is_inside_day: true,
          or_width: 20.0,
          adx: 25.0,
          sustained: true,
          strikes: {
            "ATM" => {
              mfe_pct: 40.0,
              exits: {
                hybrid_divergence: { return_pct: 35.0 }
              }
            }
          }
        }
      end

      hyps = described_class.run(mock_trades)
      compression_hyp = hyps.find { |h| h.description.include?("Inside Day") }
      expect(compression_hyp.sample_size).to eq(250)
      expect(compression_hyp.success_rate).to eq(100.0)
      expect(compression_hyp.verdict).to eq(:accepted)
      expect(compression_hyp.reason).to include("Passes BH FDR correction")
    end
  end

  describe Research::Scheduler do
    it "runs a nightly quant pipeline check successfully" do
      allow(Research::First15mEngine).to receive(:run).and_return({})

      res = described_class.run_nightly("NIFTY", 5)
      expect(res[:status]).to eq(:failed)
      expect(res[:reason]).to eq("no_data")
    end
  end
end

# rubocop:enable RSpec/MultipleExpectations
# rubocop:enable RSpec/ExampleLength
