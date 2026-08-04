# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Indicators::CachedIndicatorSource do
  describe '.series_for' do
    let(:instrument) { build_stubbed(:instrument, security_id: '13', symbol_name: 'NIFTY') }
    let(:series)     { instance_double(CandleSeries) }

    before do
      allow(Live::CandleSeriesCache).to receive(:fetch).and_return(series)
    end

    it 'delegates to CandleSeriesCache.fetch with backfill: true' do
      described_class.series_for(instrument: instrument, interval: 5)
      expect(Live::CandleSeriesCache).to have_received(:fetch).with(
        instrument: instrument,
        interval: 5,
        backfill: true
      )
    end

    it 'returns the CandleSeries from the cache' do
      result = described_class.series_for(instrument: instrument, interval: 5)
      expect(result).to eq(series)
    end

    it 'uses interval: 5 as the default' do
      described_class.series_for(instrument: instrument)
      expect(Live::CandleSeriesCache).to have_received(:fetch).with(
        instrument: instrument,
        interval: 5,
        backfill: true
      )
    end

    context 'when CandleSeriesCache returns nil (cold cache + backfill fails)' do
      before { allow(Live::CandleSeriesCache).to receive(:fetch).and_return(nil) }

      it 'returns nil without raising' do
        expect { described_class.series_for(instrument: instrument) }.not_to raise_error
        expect(described_class.series_for(instrument: instrument)).to be_nil
      end
    end
  end
end
