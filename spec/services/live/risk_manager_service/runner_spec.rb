# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Live::RiskManagerService::Runner do
  let(:harness) do
    Class.new do
      include Live::RiskManagerService::Runner
      include Live::RiskManagerService::ExitEnforcement
    end.new
  end
  let(:exit_engine) { instance_double(Live::ExitEngine) }

  before do
    allow(harness).to receive(:enforce_hard_limits_for)
    allow(harness).to receive(:enforce_selling_exits_for)
    allow(harness).to receive(:advance_trade_state_for)
    allow(harness).to receive_messages(
      enforce_premium_r_stop_for: nil, enforce_dynamic_trailing_stops_for: nil,
      enforce_profit_floor_for: nil, enforce_structure_invalidation_for: nil,
      enforce_premium_momentum_failure_for: nil, enforce_rr_profit_booking_for: nil,
      enforce_percentage_pnl_exit_for: nil, enforce_time_stop_for: nil,
      enforce_time_based_exit_for: nil
    )
  end

  describe '#run_enforcement_for_tracker' do
    context 'for a short position' do
      let(:tracker) { create(:position_tracker, position_side: 'short', status: 'active') }

      it 'runs the hard-limits check and the selling exit surface' do
        harness.send(:run_enforcement_for_tracker, tracker, exit_engine)

        expect(harness).to have_received(:enforce_hard_limits_for)
        expect(harness).to have_received(:enforce_selling_exits_for)
      end

      it 'never runs the long-only enforcement chain' do
        harness.send(:run_enforcement_for_tracker, tracker, exit_engine)

        expect(harness).not_to have_received(:enforce_premium_r_stop_for)
        expect(harness).not_to have_received(:enforce_dynamic_trailing_stops_for)
        expect(harness).not_to have_received(:enforce_structure_invalidation_for)
        expect(harness).not_to have_received(:enforce_percentage_pnl_exit_for)
      end
    end

    context 'for a long position' do
      let(:tracker) { create(:position_tracker, position_side: 'long', status: 'active') }

      it 'runs the existing long-only enforcement chain, never the selling exit surface' do
        harness.send(:run_enforcement_for_tracker, tracker, exit_engine)

        expect(harness).to have_received(:enforce_hard_limits_for)
        expect(harness).to have_received(:enforce_premium_r_stop_for)
        expect(harness).not_to have_received(:enforce_selling_exits_for)
      end
    end
  end
end
