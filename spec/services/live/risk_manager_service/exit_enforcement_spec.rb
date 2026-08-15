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
      let(:position_data) { instance_double(Positions::PositionData, high_water_mark: 500.0) } # 500 / 10000 = 5% > 2.5%

      it 'returns true' do
        expect(harness.send(:trailing_armed_for?, tracker, position_data)).to be true
      end
    end

    context 'when peak profit is below trailing activation' do
      let(:tracker) do
        instance_double(PositionTracker, entry_price: 100.0, quantity: 100)
      end
      let(:position_data) { instance_double(Positions::PositionData, high_water_mark: 100.0) } # 100 / 10000 = 1% < 2.5%

      it 'returns false' do
        expect(harness.send(:trailing_armed_for?, tracker, position_data)).to be false
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
      let(:position_data) { instance_double(Positions::PositionData, high_water_mark: 500.0) }

      it 'returns false' do
        expect(harness.send(:trailing_armed_for?, tracker, position_data)).to be false
      end
    end

    context 'when entry value is zero' do
      let(:tracker) do
        instance_double(PositionTracker, entry_price: 0.0, quantity: 0)
      end
      let(:position_data) { instance_double(Positions::PositionData, high_water_mark: 500.0) }

      it 'returns false (safe default)' do
        expect(harness.send(:trailing_armed_for?, tracker, position_data)).to be false
      end
    end
  end

  describe '#enforce_selling_exits_for' do
    let(:tracker) { create(:position_tracker, position_side: 'short', premium_received: 100.0, quantity: 1, status: 'active') }
    let(:exit_engine) { instance_double(Live::ExitEngine) }

    before do
      allow(harness).to receive_messages(risk_config: {}, pnl_snapshot: { ltp: current_ltp, pnl: 0, pnl_pct: 0, hwm_pnl: 0 })
      allow(harness).to receive(:dispatch_exit)
      allow(harness).to receive(:track_exit_path)
    end

    context 'when premium has decayed past the target' do
      let(:current_ltp) { 40.0 } # 60% decay of 100 received

      it 'dispatches an exit with the PremiumTargetRule reason' do
        harness.send(:enforce_selling_exits_for, tracker, exit_engine: exit_engine)

        expect(harness).to have_received(:dispatch_exit).with(exit_engine, tracker, a_string_matching(/PREMIUM_TARGET/))
      end
    end

    context 'when premium has expanded past the loss cap' do
      let(:current_ltp) { 350.0 } # loss = 250 vs 100 received, default cap is 2x = 200

      it 'dispatches an exit with the MaxPremiumLossRule reason (higher priority than the target rule)' do
        harness.send(:enforce_selling_exits_for, tracker, exit_engine: exit_engine)

        expect(harness).to have_received(:dispatch_exit).with(exit_engine, tracker, a_string_matching(/MAX_PREMIUM_LOSS/))
      end
    end

    context 'when neither threshold is hit' do
      let(:current_ltp) { 90.0 } # 10% decay, no loss

      it 'does not dispatch an exit' do
        harness.send(:enforce_selling_exits_for, tracker, exit_engine: exit_engine)

        expect(harness).not_to have_received(:dispatch_exit)
      end
    end
  end
end
