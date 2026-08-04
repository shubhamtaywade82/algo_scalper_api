# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PositionTracker do
  describe '#mark_exited!' do
    it 'delegates to Positions::ExitFlow' do
      tracker = create(:position_tracker, segment: 'NSE_FNO')
      allow(Positions::ExitFlow).to receive(:call).and_return(tracker)

      tracker.mark_exited!(exit_reason: 'stop')

      expect(Positions::ExitFlow).to have_received(:call).with(
        tracker: tracker,
        exit_price: nil,
        exited_at: nil,
        exit_reason: 'stop'
      )
    end
  end

  describe '#lock_breakeven!' do
    it 'updates meta through Positions::MetaUpdater' do
      tracker = create(:position_tracker, segment: 'NSE_FNO', meta: {})
      updater = instance_double(Positions::MetaUpdater, update!: true)
      allow(Positions::MetaUpdater).to receive(:new).with(tracker: tracker).and_return(updater)

      tracker.lock_breakeven!

      expect(updater).to have_received(:update!)
    end
  end
end
