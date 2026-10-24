# frozen_string_literal: true

require 'rails_helper'

RSpec.describe OptionsBuying::ChainRadarJob do
  let(:index_cfg) { { key: 'NIFTY', sid: '13', segment: 'IDX_I' } }

  before do
    allow(IndexConfigLoader).to receive(:load_indices).and_return([index_cfg])
    allow(OptionsBuying::Mode).to receive(:chain_radar_enabled?).and_return(true)
    allow(TradingSession::Service).to receive(:market_closed?).and_return(false)
    allow(OptionsBuying::ChainRadar).to receive(:scan!)
  end

  describe '#perform' do
    it 'scans chain radar for each index' do
      expect(OptionsBuying::ChainRadar).to receive(:scan!).with('NIFTY')

      described_class.perform_now
    end

    context 'when chain radar is disabled' do
      before do
        allow(OptionsBuying::Mode).to receive(:chain_radar_enabled?).and_return(false)
      end

      it 'does not scan' do
        expect(OptionsBuying::ChainRadar).not_to receive(:scan!)

        described_class.perform_now
      end
    end

    context 'when market is closed' do
      before do
        allow(TradingSession::Service).to receive(:market_closed?).and_return(true)
      end

      it 'does not scan' do
        expect(OptionsBuying::ChainRadar).not_to receive(:scan!)

        described_class.perform_now
      end
    end
  end
end
