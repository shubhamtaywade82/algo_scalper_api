# frozen_string_literal: true

require 'rails_helper'

RSpec.describe OptionsBuying::CandlePrecomputeJob do
  describe '#perform' do
    let(:instrument) { instance_double(Instrument) }
    let(:series) { instance_double(CandleSeries, load_from_raw: nil, to_hash: { 'timestamp' => [1] }) }

    before do
      allow_any_instance_of(described_class).to receive(:market_hours?).and_return(true)
      allow(IndexConfigLoader).to receive(:load_indices).and_return([
        { key: 'NIFTY', sid: 13, segment: 'index' }
      ])
      allow(Instrument).to receive(:find_by).with(security_id: 13).and_return(instrument)
      allow(CandleSeries).to receive(:new).and_return(series)
      allow(OptionsBuying::StateStore).to receive(:cache_index_candles)
      allow(instrument).to receive(:intraday_ohlc).and_return([{ timestamp: Time.current, close: 1 }])
      allow(instrument).to receive(:historical_ohlc).and_return([{ timestamp: Time.current, close: 1 }])
    end

    it 'uses intraday candles for intraday timeframes' do
      described_class.new.perform

      expect(instrument).to have_received(:intraday_ohlc).with(interval: '5', days: 10)
      expect(OptionsBuying::StateStore).to have_received(:cache_index_candles).with('NIFTY', '5', { 'timestamp' => [1] })
    end

    it 'uses historical candles for daily timeframe' do
      described_class.new.perform

      expect(instrument).to have_received(:historical_ohlc)
    end
  end
end
