# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Positions::ExitFlow do
  describe '.call' do
    it 'runs exit orchestration and returns tracker' do
      tracker = instance_double(PositionTracker, id: 12)
      state_machine = instance_double(Positions::States::PositionStateMachine, transition_to!: true)
      cache = instance_double(
        Live::RedisPnlCache,
        fetch_pnl: { pnl: 10, pnl_pct: 0.2, hwm_pnl: 12, hwm_pnl_pct: 0.3 },
        sync_pnl_to_database: true
      )

      allow(tracker).to receive_messages(state_machine: state_machine, send: nil)
      allow(Live::RedisPnlCache).to receive(:instance).and_return(cache)
      allow(Positions::DailyPnlRecorder).to receive(:call)
      allow(Positions::FeedSubscription).to receive(:unsubscribe)

      result = described_class.call(tracker: tracker)

      expect(state_machine).to have_received(:transition_to!).with(:exited)
      expect(Positions::DailyPnlRecorder).to have_received(:call).with(tracker: tracker)
      expect(Positions::FeedSubscription).to have_received(:unsubscribe).with(tracker: tracker)
      expect(result).to eq(tracker)
    end
  end
end
