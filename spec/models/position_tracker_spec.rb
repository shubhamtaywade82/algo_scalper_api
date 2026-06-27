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
    it 'sets breakeven_locked column directly' do
      tracker = create(:position_tracker, segment: 'NSE_FNO', breakeven_locked: false)

      expect { tracker.lock_breakeven! }.to change { tracker.reload.breakeven_locked }.to(true)
    end
  end
end
