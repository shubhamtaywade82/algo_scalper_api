# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Positions::ManualCloseService do
  describe '.call' do
    it 'returns invalid_id when id is blank' do
      outcome = described_class.call(tracker_id: '')
      expect(outcome[:status]).to eq(:bad_request)
      expect(outcome[:json][:error]).to eq('invalid_id')
    end

    it 'returns not_found when no active tracker' do
      outcome = described_class.call(tracker_id: '999999999')
      expect(outcome[:status]).to eq(:not_found)
      expect(outcome[:json][:error]).to eq('not_found')
    end

    context 'with an active tracker' do
      let(:tracker) { create(:position_tracker, segment: 'NSE_FNO', security_id: '50073') }
      let(:exit_engine) { instance_double(Live::ExitEngine, start: true, stop: true) }

      before do
        allow(TradingSystem::OrderRouter).to receive(:new).and_return(instance_double(TradingSystem::OrderRouter))
        allow(Live::ExitEngine).to receive(:new).and_return(exit_engine)
      end

      it 'returns ok when exit succeeds' do
        allow(exit_engine).to receive(:execute_exit).and_return(
          { success: true, reason: 'MANUAL_DASHBOARD_CLOSE', exit_price: 100.0 }
        )

        outcome = described_class.call(tracker_id: tracker.id)

        expect(outcome[:status]).to eq(:ok)
        expect(outcome[:json][:success]).to be(true)
        expect(exit_engine).to have_received(:execute_exit).with(
          an_object_having_attributes(id: tracker.id),
          'MANUAL_DASHBOARD_CLOSE'
        )
      end

      it 'maps exit_lock_held to conflict' do
        allow(exit_engine).to receive(:execute_exit).and_return(
          { success: false, reason: 'exit_lock_held' }
        )

        outcome = described_class.call(tracker_id: tracker.id)

        expect(outcome[:status]).to eq(:conflict)
        expect(outcome[:json][:error]).to eq('exit_lock_held')
      end

      it 'stops exit engine after call' do
        allow(exit_engine).to receive(:execute_exit).and_return({ success: true, reason: 'ok' })

        described_class.call(tracker_id: tracker.id)

        expect(exit_engine).to have_received(:stop)
      end
    end
  end
end
