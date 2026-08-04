# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Signal::Scheduler do
  let(:scheduler) { described_class.new(period: 1) }
  let(:index_cfg) { { key: 'NIFTY', segment: 'IDX_I', sid: '13' } }

  describe '#process_index' do
    before do
      allow(Signal::Engine).to receive(:run_for)
    end

    # Market open/closed gating happens in the scheduler loop, not inside #process_index.
    it 'always delegates to Signal::Engine.run_for when invoked directly' do
      allow(TradingSession::Service).to receive(:market_closed?).and_return(true)

      scheduler.send(:process_index, index_cfg)

      expect(Signal::Engine).to have_received(:run_for).with(
        index_cfg,
        regime_state: instance_of(Market::RegimeState)
      )
    end
  end
end
