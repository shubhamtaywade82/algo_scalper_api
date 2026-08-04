# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Research::RegimeExitReport do
  def make_candidate(strategy_name:, strike_label: "ATM", regime: {}, exit_simulations: {})
    signal = Research::Signal.create!(
      underlying_symbol: "NIFTY", signal_timestamp: Time.zone.parse("2026-07-13 09:45:00"),
      direction: "bullish", spot_price: 25_000.0, strategy_name: strategy_name,
      metadata: { "regime" => regime }
    )
    Research::OptionCandidate.create!(
      research_signal: signal, underlying_symbol: "NIFTY", expiry_flag: "WEEK", option_type: "CE",
      strike_label: strike_label, strike_distance: 0, entry_model: "next_candle_open",
      status: "scored", exit_simulations: exit_simulations
    )
  end

  def exits_with(fixed_30_return:, hold_to_close_return:)
    Research::ExitCaptureAnalyzer::STRATEGY_NAMES.index_with do |name|
      return_pct = if name == :fixed_30
                     fixed_30_return
                   else
                     (name == :hold_to_close ? hold_to_close_return : 0.0)
                   end
      {
        "exit_price" => 100.0, "exit_time" => "2026-07-13T10:00:00+05:30", "exit_reason" => "market_close",
        "holding_time_minutes" => 30, "capture_efficiency" => 0.5, "opportunity_retention_ratio" => 0.5,
        "lost_profit_points" => 1.0, "leakage_time" => 0, "leakage_speed" => 0.0, "giveback_pct" => 0.0,
        "return_pct" => return_pct, "win" => return_pct.positive?
      }
    end.stringify_keys
  end

  describe '.call' do
    it 'groups scored regime_scan candidates by regime dimensions and ranks strategies by avg_return_pct' do
      make_candidate(
        strategy_name: "regime_scan", regime: { "trend" => "strong_bullish", "volatility_regime" => "expanding" },
        exit_simulations: exits_with(fixed_30_return: 10.0, hold_to_close_return: -5.0)
      )
      make_candidate(
        strategy_name: "regime_scan", regime: { "trend" => "strong_bullish", "volatility_regime" => "expanding" },
        exit_simulations: exits_with(fixed_30_return: 20.0, hold_to_close_return: -5.0)
      )

      buckets = described_class.call(scope: Research::OptionCandidate.where(status: "scored"),
                                     dimensions: %w[trend volatility_regime])

      expect(buckets.size).to eq(1)
      bucket = buckets.first
      expect(bucket[:context]).to eq("trend" => "strong_bullish", "volatility_regime" => "expanding")
      expect(bucket[:sample_size]).to eq(2)
      expect(bucket[:best_strategy]).to eq(:fixed_30)
      expect(bucket[:best_strategy_return_pct]).to eq(15.0)
      expect(bucket[:strategies][:fixed_30][:avg_return_pct]).to eq(15.0)
      expect(bucket[:strategies][:hold_to_close][:avg_return_pct]).to eq(-5.0)
    end

    it 'separates buckets by distinct regime context' do
      make_candidate(strategy_name: "regime_scan", regime: { "trend" => "strong_bullish" },
                     exit_simulations: exits_with(fixed_30_return: 10.0, hold_to_close_return: 0.0))
      make_candidate(strategy_name: "regime_scan", regime: { "trend" => "neutral" },
                     exit_simulations: exits_with(fixed_30_return: -10.0, hold_to_close_return: 0.0))

      buckets = described_class.call(scope: Research::OptionCandidate.where(status: "scored"),
                                     dimensions: %w[trend])

      expect(buckets.size).to eq(2)
      expect(buckets.map { |b| b[:context]["trend"] }).to contain_exactly("strong_bullish", "neutral")
    end

    it 'excludes candidates whose signal did not come from the regime scanner' do
      make_candidate(strategy_name: "manual_rake_run", regime: { "trend" => "strong_bullish" },
                     exit_simulations: exits_with(fixed_30_return: 10.0, hold_to_close_return: 0.0))

      buckets = described_class.call(scope: Research::OptionCandidate.where(status: "scored"),
                                     dimensions: %w[trend])

      expect(buckets).to be_empty
    end

    it 'excludes candidates with an unrecognized strike_label' do
      make_candidate(strategy_name: "regime_scan", strike_label: "ATM+1", regime: { "trend" => "strong_bullish" },
                     exit_simulations: exits_with(fixed_30_return: 10.0, hold_to_close_return: 0.0))

      buckets = described_class.call(scope: Research::OptionCandidate.where(status: "scored"),
                                     dimensions: %w[trend])

      expect(buckets).to be_empty
    end

    it 'defaults missing regime dimensions to "unknown"' do
      make_candidate(strategy_name: "regime_scan", regime: { "trend" => "strong_bullish" },
                     exit_simulations: exits_with(fixed_30_return: 10.0, hold_to_close_return: 0.0))

      buckets = described_class.call(scope: Research::OptionCandidate.where(status: "scored"),
                                     dimensions: %w[trend volatility_regime])

      expect(buckets.first[:context]).to eq("trend" => "strong_bullish", "volatility_regime" => "unknown")
    end
  end
end
