# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Signal::Scheduler do
  let(:scheduler) { described_class.new(period: 1) }
  let(:index_cfg) { { key: 'NIFTY', segment: 'IDX_I', sid: '13' } }

  describe '#process_index' do
    context 'when market is closed' do
      before do
        allow(TradingSession::Service).to receive(:market_closed?).and_return(true)
        allow(scheduler).to receive(:evaluate_supertrend_signal)
      end

      it 'returns early without processing' do
        scheduler.send(:process_index, index_cfg)
        expect(scheduler).not_to have_received(:evaluate_supertrend_signal)
      end
    end

    context 'when market is open' do
      before do
        allow(TradingSession::Service).to receive(:market_closed?).and_return(false)
        allow(scheduler).to receive(:evaluate_supertrend_signal).and_return(nil)
      end

      it 'processes the index' do
        scheduler.send(:process_index, index_cfg)
        expect(scheduler).to have_received(:evaluate_supertrend_signal).with(index_cfg)
      end
    end
  end
end
