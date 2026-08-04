# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Signal::Engine do
  let(:index_cfg) { { key: 'NIFTY', segment: 'IDX_I', sid: '13' } }

  describe '.run_for' do
    context 'when market is closed' do
      before do
        allow(TradingSession::Service).to receive(:market_closed?).and_return(true)
      end

      it 'returns early without processing' do
        # debug can be called with a block, so we check it's called
        expect(Rails.logger).to receive(:debug).at_least(:once)
        described_class.run_for(index_cfg)
      end
    end

    context 'when market is open' do
      before do
        allow(TradingSession::Service).to receive(:market_closed?).and_return(false)
        allow(IndexInstrumentCache.instance).to receive(:get_or_fetch).and_return(nil)
      end

      it 'proceeds with analysis' do
        expect(IndexInstrumentCache.instance).to receive(:get_or_fetch).with(index_cfg)
        described_class.run_for(index_cfg)
      end
    end
  end
end
