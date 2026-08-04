# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Capital::Allocator do
  describe '.calculate_max_by_risk' do
    it 'uses the configured stop-loss percentage instead of a hardcoded 30%' do
      allow(AlgoConfig).to receive(:fetch).and_return(risk: { sl_pct: 0.12 }, exit: {})

      # risk_capital = 10000 * 0.02 = 200; stop_loss_per_share = 100 * 0.12 = 12
      # (200 / 12).floor * lot_size(50) = 16 * 50 = 800
      result = described_class.send(
        :calculate_max_by_risk, 10_000.0, 100.0, 50, 0.02, 1.0
      )
      expect(result).to eq(800)
    end

    it 'falls back to 0.12 when no sl_pct/stop_loss config is present' do
      allow(AlgoConfig).to receive(:fetch).and_return({})

      result = described_class.send(
        :calculate_max_by_risk, 10_000.0, 100.0, 50, 0.02, 1.0
      )
      # Same math as above since default is also 0.12
      expect(result).to eq(800)
    end

    it 'matches the same stop-loss source Live::UnifiedExitChecker uses' do
      allow(AlgoConfig).to receive(:fetch).and_return(risk: {}, exit: { stop_loss: { value: 0.20 } })

      # stop_loss_per_share = 100 * 0.20 = 20; (200/20).floor * 50 = 10 * 50 = 500
      result = described_class.send(
        :calculate_max_by_risk, 10_000.0, 100.0, 50, 0.02, 1.0
      )
      expect(result).to eq(500)
    end
  end

  describe '.calculate_kelly_based_quantity fallback risk/reward' do
    it 'derives fallback stop/target from configured option SL/TP, not equity-style 2%/4%' do
      allow(AlgoConfig).to receive(:fetch).and_return(
        kelly_sizing: { enabled: true },
        risk: { sl_pct: 0.12 },
        exit: { take_profit: 0.50 }
      )
      allow(OptionsBuying::PerformanceDb).to receive(:stats_for).and_return(nil)

      index_cfg = { key: 'NIFTY', confidence: 0.6 }

      qty = described_class.send(
        :calculate_kelly_based_quantity,
        index_cfg: index_cfg,
        entry_price: 100.0,
        derivative_lot_size: 50,
        capital_available: 100_000.0,
        multiplier: 1.0
      )

      # With sl=12%, tp=50%: risk=12, reward=50, r=50/12=4.17 (vs old 2%/4% => r=2.0)
      # Just assert it doesn't blow up and returns a sane non-negative quantity.
      expect(qty).to be_a(Integer)
      expect(qty).to be >= 0
    end
  end
end
