# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ClearCarriedOvernightPositionsJob do
  let(:exit_engine) { instance_double(Live::ExitEngine, start: nil, stop: nil) }

  before do
    allow(TradingSystem::OrderRouter).to receive(:new).and_return(instance_double(TradingSystem::OrderRouter))
    allow(Live::ExitEngine).to receive(:new).and_return(exit_engine)
    allow(exit_engine).to receive(:execute_exit).and_return({ success: true, reason: 'ok' })
  end

  it 'force-closes a stale overnight position that is not a valid carry' do
    stale = create(:position_tracker, segment: 'NSE_FNO', created_at: 2.days.ago)
    allow(OptionsBuying::CarryPolicy).to receive(:carry_still_valid?).and_return(false)

    described_class.new.perform

    expect(exit_engine).to have_received(:execute_exit).with(stale, anything)
  end

  it 'skips a position that is still a valid positional carry' do
    create(:position_tracker, segment: 'NSE_FNO', created_at: 2.days.ago)
    allow(OptionsBuying::CarryPolicy).to receive(:carry_still_valid?).and_return(true)

    described_class.new.perform

    expect(exit_engine).not_to have_received(:execute_exit)
  end

  it 'clears the non-carry position while holding the carried one' do
    carry = create(:position_tracker, segment: 'NSE_FNO', created_at: 2.days.ago)
    stale = create(:position_tracker, segment: 'NSE_FNO', created_at: 2.days.ago)
    allow(OptionsBuying::CarryPolicy).to receive(:carry_still_valid?) { |t| t.id == carry.id }

    described_class.new.perform

    expect(exit_engine).to have_received(:execute_exit).with(stale, anything)
    expect(exit_engine).not_to have_received(:execute_exit).with(carry, anything)
  end
end
