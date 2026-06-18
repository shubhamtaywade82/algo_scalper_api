# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Live::RiskManagerService::ExitEnforcement do
  let(:harness) do
    Class.new do
      include Live::RiskManagerService::ExitEnforcement
    end.new
  end

  describe '#trailing_armed_for?' do
    before do
      allow(AlgoConfig).to receive(:fetch).and_return({
        risk: {
          trailing: { enabled: true, activation_pct: 0.025 }
        }
      })
    end

    context 'when peak profit exceeds trailing activation' do
      let(:tracker) do
        instance_double(PositionTracker, entry_price: 100.0, quantity: 100)
      end
      let(:snapshot) { { hwm_pnl: 500.0 } } # 500 / 10000 = 5% > 2.5%

      it 'returns true' do
        expect(harness.send(:trailing_armed_for?, tracker, snapshot)).to be true
      end
    end

    context 'when peak profit is below trailing activation' do
      let(:tracker) do
        instance_double(PositionTracker, entry_price: 100.0, quantity: 100)
      end
      let(:snapshot) { { hwm_pnl: 100.0 } } # 100 / 10000 = 1% < 2.5%

      it 'returns false' do
        expect(harness.send(:trailing_armed_for?, tracker, snapshot)).to be false
      end
    end

    context 'when trailing is disabled' do
      before do
        allow(AlgoConfig).to receive(:fetch).and_return({
          risk: { trailing: { enabled: false, activation_pct: 0.025 } }
        })
      end

      let(:tracker) do
        instance_double(PositionTracker, entry_price: 100.0, quantity: 100)
      end
      let(:snapshot) { { hwm_pnl: 500.0 } }

      it 'returns false' do
        expect(harness.send(:trailing_armed_for?, tracker, snapshot)).to be false
      end
    end

    context 'when entry value is zero' do
      let(:tracker) do
        instance_double(PositionTracker, entry_price: 0.0, quantity: 0)
      end
      let(:snapshot) { { hwm_pnl: 500.0 } }

      it 'returns false (safe default)' do
        expect(harness.send(:trailing_armed_for?, tracker, snapshot)).to be false
      end
    end
  end

  describe '#carry_held?' do
    let(:tracker) { instance_double(PositionTracker) }

    it 'is true when the tracker is a still-valid positional carry (skip EOD force-close)' do
      allow(OptionsBuying::CarryPolicy).to receive(:carry_still_valid?).with(tracker).and_return(true)
      expect(harness.send(:carry_held?, tracker)).to be(true)
    end

    it 'is false for a normal intraday position' do
      allow(OptionsBuying::CarryPolicy).to receive(:carry_still_valid?).with(tracker).and_return(false)
      expect(harness.send(:carry_held?, tracker)).to be(false)
    end

    it 'fails safe (false → still squares off) when the carry check raises' do
      allow(OptionsBuying::CarryPolicy).to receive(:carry_still_valid?).and_raise(StandardError, 'boom')
      expect(harness.send(:carry_held?, tracker)).to be(false)
    end
  end
end
