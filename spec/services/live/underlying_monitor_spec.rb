# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Live::UnderlyingMonitor do
  let(:position_data) do
    instance_double(
      Positions::ActiveCache::PositionData,
      tracker_id: 42,
      underlying_segment: 'IDX_I',
      underlying_security_id: '13',
      underlying_symbol: 'NIFTY',
      index_key: 'NIFTY',
      position_direction: :bullish,
      underlying_ltp: nil
    )
  end

  after { described_class.reset_cache! }

  describe '.evaluate' do
    context 'when underlying metadata is missing' do
      it 'returns default state' do
        allow(position_data).to receive(:underlying_segment).and_return(nil)
        result = described_class.evaluate(position_data)

        expect(result.trend_score).to be_nil
        expect(result.bos_state).to eq(:unknown)
      end
    end

    context 'when data is available' do
      let(:instrument) { instance_double(Instrument, candle_series: candle_series) }
      let(:candle_series) do
        instance_double(CandleSeries, candles: candle_objects, previous_swing_low: 95.0, previous_swing_high: 110.0)
      end
      let(:candle_objects) do
        Array.new(30) do |i|
          OpenStruct.new(
            high: 100 + i,
            low: 90 + i,
            close: 95 + i
          )
        end
      end

      before do
        allow(IndexInstrumentCache.instance).to receive(:get_or_fetch).and_return(instrument)
        allow(Signal::TrendScorer).to receive(:compute_direction).and_return(
          trend_score: 18,
          breakdown: { mtf: 4 }
        )
        allow(Live::TickCache).to receive(:ltp).and_return(21_500)
      end

      it 'computes underlying state with caching' do
        first = described_class.evaluate(position_data)
        second = described_class.evaluate(position_data)

        expect(first.trend_score).to eq(18)
        expect(first.mtf_confirm).to be true
        expect(first.ltp).to eq(21_500)
        expect(second.trend_score).to eq(18)
        expect(Signal::TrendScorer).to have_received(:compute_direction).once
      end
    end
  end
end
