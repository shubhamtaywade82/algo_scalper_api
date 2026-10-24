# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Portfolio::ProfitLockEngine do
  # Stub the PnlTracker and DrawdownGuard to test the engine in isolation
  before do
    described_class.reset_levels_cache!
    allow(Portfolio::DrawdownGuard).to receive(:triggered?).and_return(false)
    allow(Portfolio::PnlTracker).to receive(:update_lock)
    allow(AlgoConfig).to receive(:fetch).and_return(config)
  end

  let(:config) do
    {
      profit_lock: {
        enabled: true,
        levels: [
          { trigger: 20_000, lock_ratio: 0.60 },
          { trigger: 35_000, lock_ratio: 0.70 },
          { trigger: 50_000, lock_ratio: 0.73 }
        ]
      }
    }
  end

  after { described_class.reset_levels_cache! }

  describe '.determine_level' do
    it 'returns 0 when pnl is below all thresholds' do
      expect(described_class.determine_level(5_000)).to eq(0)
    end

    it 'returns 1 when pnl is exactly at the first threshold' do
      expect(described_class.determine_level(20_000)).to eq(1)
    end

    it 'returns 2 when pnl is between 35k and 50k' do
      expect(described_class.determine_level(40_000)).to eq(2)
    end

    it 'returns 3 when pnl is above all thresholds' do
      expect(described_class.determine_level(55_000)).to eq(3)
    end
  end

  describe '.levels' do
    context 'when config levels are provided' do
      it 'loads levels from config' do
        expect(described_class.levels.first[:trigger]).to eq(20_000)
      end
    end

    context 'when config is missing or malformed' do
      let(:config) { { profit_lock: { enabled: true } } }

      it 'falls back to DEFAULT_LEVELS' do
        expect(described_class.levels).to eq(described_class::DEFAULT_LEVELS)
      end
    end
  end

  describe '.evaluate!' do
    context 'when profit_lock is disabled' do
      let(:config) { { profit_lock: { enabled: false } } }

      it 'returns false without touching PnlTracker' do
        expect(Portfolio::PnlTracker).not_to receive(:net_pnl)
        expect(described_class.evaluate!).to be(false)
      end
    end

    context 'when DrawdownGuard has already triggered' do
      before do
        allow(Portfolio::DrawdownGuard).to receive(:triggered?).and_return(true)
      end

      it 'is a no-op and returns false' do
        expect(Portfolio::PnlTracker).not_to receive(:net_pnl)
        expect(described_class.evaluate!).to be(false)
      end
    end

    context 'when net PnL is below all thresholds' do
      before do
        allow(Portfolio::PnlTracker).to receive_messages(net_pnl: 5_000.0, peak_pnl: 5_000.0, current_level: 0, locked_floor: 0.0)
      end

      it 'returns false and does not trigger guard' do
        expect(Portfolio::DrawdownGuard).not_to receive(:trigger_global_exit!)
        expect(described_class.evaluate!).to be(false)
      end
    end

    context 'when net PnL crosses ₹20k for the first time' do
      before do
        allow(Portfolio::PnlTracker).to receive_messages(net_pnl: 22_000.0, peak_pnl: 0.0, current_level: 0, locked_floor: 13_200.0) # 22k × 0.60
      end

      it 'calls update_lock with level 1 and 60% floor' do
        expect(Portfolio::PnlTracker).to receive(:update_lock).with(
          new_peak: 22_000.0,
          new_floor: 13_200.0,
          new_level: 1
        )
        described_class.evaluate!
      end

      it 'does not trigger guard when net > floor' do
        expect(Portfolio::DrawdownGuard).not_to receive(:trigger_global_exit!)
        described_class.evaluate!
      end
    end

    context 'when net PnL drops below the locked floor' do
      before do
        allow(Portfolio::PnlTracker).to receive_messages(net_pnl: 5_500.0, peak_pnl: 15_000.0, current_level: 1, locked_floor: 6_000.0)
        allow(Portfolio::DrawdownGuard).to receive(:trigger_global_exit!)
      end

      it 'returns true and triggers the guard' do
        expect(Portfolio::DrawdownGuard).to receive(:trigger_global_exit!).with(
          net_pnl: 5_500.0,
          floor: 6_000.0,
          level: 1
        )
        expect(described_class.evaluate!).to be(true)
      end
    end

    context 'when peak ratchets above a higher level trigger' do
      before do
        # PnL peaked at ₹40k (Level 2), net ₹30k still above floor
        # floor = 40k × 0.70 = 28k (stored from previous ratchet)
        allow(Portfolio::PnlTracker).to receive_messages(net_pnl: 30_000.0, peak_pnl: 40_000.0, current_level: 2, locked_floor: 28_000.0)
      end

      it 'does not downgrade the level or breach the guard' do
        expect(Portfolio::DrawdownGuard).not_to receive(:trigger_global_exit!)
        expect(described_class.evaluate!).to be(false)
      end
    end
  end
end
