# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Scalp::FeeAwareExitTargets do
  # NIFTY-ish fixture: entry 150, qty 75 -> position value 11,250.
  # Statutory round-trip fees 72.88/11,250 = 0.00648; tick spread 1.0 -> spread_pct = 0.00667.
  let(:nifty_tracker) do
    instance_double(PositionTracker, entry_price: 150.0, quantity: 75)
  end

  # SENSEX fee-hostile fixture: entry 50, qty 20 -> position value 1,000.
  # Statutory round-trip fees 49.48/1,000 = 0.04948; estimated spread 50 x 0.01 x 2 = 1.0 -> 0.02.
  let(:sensex_tracker) do
    instance_double(PositionTracker, entry_price: 50.0, quantity: 20)
  end

  let(:quote_tick) do
    MarketTick.new(
      segment: 'NSE_FNO', security_id: 'S1', ltp: 150.0,
      timestamp: Time.current, oi: 0, oi_change: 0,
      bid: 149.5, ask: 150.5, volume: 0, prev_close: 0.0
    )
  end

  before do
    allow(AlgoConfig).to receive(:fetch).and_return({
      risk: { scalp_exit: { enabled: true } },
      broker_fees: { enabled: true, fee_per_order: 20 }
    })
    allow(Live::TickQuery).to receive(:for).and_return(nil)
  end

  describe '.enabled?' do
    it 'is opt-in: absent section means disabled' do
      allow(AlgoConfig).to receive(:fetch).and_return({ risk: {} })
      expect(described_class.enabled?).to be false
    end

    it 'is enabled when explicitly configured' do
      expect(described_class.enabled?).to be true
    end
  end

  describe '#friction_pct' do
    it 'combines fees and live tick spread as fractions of premium' do
      targets = described_class.new(nifty_tracker, tick: quote_tick)
      # statutory round-trip fees 72.88/11250 + spread 1.0/150
      expect(targets.friction_pct).to be_within(0.0001).of(0.0064784 + 0.0066667)
    end

    it 'falls back to the configured spread estimate without a live quote' do
      targets = described_class.new(sensex_tracker)
      # statutory round-trip fees 49.48/1000 + estimate (50 x 0.01 x 2)/50
      expect(targets.friction_pct).to be_within(0.0001).of(0.0494828 + 0.02)
    end

    it 'excludes fees when broker fee simulation is disabled' do
      allow(AlgoConfig).to receive(:fetch).and_return({
        risk: { scalp_exit: { enabled: true } },
        broker_fees: { enabled: false, fee_per_order: 20 }
      })
      targets = described_class.new(sensex_tracker)
      expect(targets.friction_pct).to be_within(0.0001).of(0.02)
    end

    it 'returns nil for unusable position economics (corrupt tracker)' do
      tracker = instance_double(PositionTracker, entry_price: 0.0, quantity: 75)
      expect(described_class.new(tracker).friction_pct).to be_nil
    end

    it 'ignores a crossed or one-sided quote (falls back to estimate)' do
      crossed = MarketTick.new(
        segment: 'NSE_FNO', security_id: 'S1', ltp: 50.0,
        timestamp: Time.current, oi: 0, oi_change: 0,
        bid: 0.0, ask: 0.0, volume: 0, prev_close: 0.0
      )
      targets = described_class.new(sensex_tracker, tick: crossed)
      expect(targets.friction_pct).to be_within(0.0001).of(0.0494828 + 0.02)
    end
  end

  describe '#min_target_pct' do
    it 'returns the base target when the layer is disabled' do
      allow(AlgoConfig).to receive(:fetch).and_return({ risk: {} })
      targets = described_class.new(sensex_tracker)
      expect(targets.min_target_pct(0.05)).to eq(0.05)
    end

    it 'keeps the base for fee-efficient positions (friction tiny)' do
      targets = described_class.new(nifty_tracker, tick: quote_tick)
      # 3 x 0.01315 = 0.0394 < 0.05
      expect(targets.min_target_pct(0.05)).to eq(0.05)
    end

    it 'raises the target for fee-hostile positions (SENSEX cheap premium)' do
      targets = described_class.new(sensex_tracker)
      # friction 0.0695 -> 3 x 0.0695 = 0.2084 > 0.05
      expect(targets.min_target_pct(0.05)).to be_within(0.0001).of(0.2084)
    end

    it 'caps the fee floor at max_target_pct' do
      # qty 1 x entry 30 -> value 30; statutory fees 47.27/30 = 1.576; floor would be ~4.8 -> capped at 0.30
      tracker = instance_double(PositionTracker, entry_price: 30.0, quantity: 1)
      targets = described_class.new(tracker)
      expect(targets.min_target_pct(0.05)).to eq(0.30)
    end

    it 'never lowers a base target that is already above the cap' do
      # Same fee-hostile economics, but base 0.50 must survive the cap untouched.
      tracker = instance_double(PositionTracker, entry_price: 30.0, quantity: 1)
      targets = described_class.new(tracker)
      expect(targets.min_target_pct(0.50)).to eq(0.50)
    end

    it 'falls back to base when friction is unknowable' do
      tracker = instance_double(PositionTracker, entry_price: 0.0, quantity: 75)
      targets = described_class.new(tracker)
      expect(targets.min_target_pct(0.07)).to eq(0.07)
    end
  end

  describe '#breakeven_lock_price' do
    it 'covers the round-trip fees and full spread spread over quantity' do
      # entry 100, qty 50, statutory round trip 58.61 (brokerage + STT + txn
      # + GST + stamp + SEBI per Orders::ChargesCalculator),
      # estimated full spread 100 x 0.01 x 2 = 2.0
      # 100 + (58.61 + 2.0)/50 = 101.21 (net-zero on the whole trade, not the
      # exit leg alone — review P2)
      tracker = instance_double(PositionTracker, entry_price: 100.0, quantity: 50)
      targets = described_class.new(tracker)
      expect(targets.breakeven_lock_price).to eq(101.21)
    end

    it 'uses the live half spread when a quote is available' do
      tracker = instance_double(PositionTracker, entry_price: 100.0, quantity: 50)
      tick = MarketTick.new(
        segment: 'NSE_FNO', security_id: 'S1', ltp: 100.0,
        timestamp: Time.current, oi: 0, oi_change: 0,
        bid: 98.0, ask: 102.0, volume: 0, prev_close: 0.0
      )
      targets = described_class.new(tracker, tick: tick)
      # spread 4 (full, both legs) + statutory round-trip fees 58.61:
      # 100 + (58.61 + 4.0)/50 = 101.25
      expect(targets.breakeven_lock_price).to eq(101.25)
    end

    it 'returns nil for unusable economics' do
      tracker = instance_double(PositionTracker, entry_price: 100.0, quantity: 0)
      expect(described_class.new(tracker).breakeven_lock_price).to be_nil
    end
  end

  describe '#breakeven_armed?' do
    it 'arms once peak covers friction x arm factor' do
      targets = described_class.new(sensex_tracker)
      # friction 0.0695 -> armed at 0.0834
      expect(targets.breakeven_armed?(0.09)).to be true
      expect(targets.breakeven_armed?(0.08)).to be false
    end

    it 'never arms on unknowable friction' do
      tracker = instance_double(PositionTracker, entry_price: 0.0, quantity: 75)
      expect(described_class.new(tracker).breakeven_armed?(0.50)).to be false
    end
  end

  describe 'strict config reads' do
    it 'raises ConfigurationError on garbage numeric config' do
      allow(AlgoConfig).to receive(:fetch).and_return({
        risk: { scalp_exit: { enabled: true, friction_multiple: 'lots' } },
        broker_fees: { enabled: true, fee_per_order: 20 }
      })
      targets = described_class.new(nifty_tracker, tick: quote_tick)
      expect { targets.min_target_pct(0.05) }.to raise_error(Errors::ConfigurationError, /friction_multiple/)
    end

    it 'accepts numeric strings' do
      allow(AlgoConfig).to receive(:fetch).and_return({
        risk: { scalp_exit: { enabled: true, friction_multiple: '2.5' } },
        broker_fees: { enabled: true, fee_per_order: 20 }
      })
      targets = described_class.new(sensex_tracker)
      # friction 0.0695 -> 2.5 x 0.0695 = 0.1737 > 0.05
      expect(targets.min_target_pct(0.05)).to be_within(0.0001).of(0.1737)
    end
  end
end
