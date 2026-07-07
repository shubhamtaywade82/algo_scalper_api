# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Smc::StructureEventRecorder do
  let(:instrument) { create(:instrument, symbol_name: 'NIFTY') }

  before do
    allow(AlgoConfig).to receive(:fetch).and_return({ signals: { smc_event_store_publish: true } })
  end

  describe '.record!' do
    it 'returns an empty array when the event store flag is disabled' do
      allow(AlgoConfig).to receive(:fetch).and_return({ signals: { smc_event_store_publish: false } })
      series = build(:candle_series, :five_minute, :with_candles)
      allow(instrument).to receive(:candles).with(interval: '5').and_return(series)

      expect(described_class.record!(instrument: instrument, interval: '5')).to eq([])
      expect(SmcEvent.count).to eq(0)
    end

    it 'returns an empty array when the series has fewer than 5 candles' do
      series = build(:candle_series, :five_minute)
      series.add_candle(build(:candle))
      allow(instrument).to receive(:candles).with(interval: '5').and_return(series)

      expect(described_class.record!(instrument: instrument, interval: '5')).to eq([])
    end

    it 'persists a swing_high event for a detected swing high' do
      series = build(:candle_series, :five_minute)
      # Swing candidate at index 3 satisfies CandleSeries#swing_high?'s real boundary
      # check (index >= lookback(3) && index + lookback < candles.size) with 7 candles.
      candles = [
        build(:candle, high: 100, low: 90, close: 95),
        build(:candle, high: 101, low: 91, close: 96),
        build(:candle, high: 102, low: 92, close: 97),
        build(:candle, high: 120, low: 100, close: 110), # swing high candidate
        build(:candle, high: 108, low: 95, close: 97),
        build(:candle, high: 106, low: 93, close: 96),
        build(:candle, high: 104, low: 91, close: 95)
      ]
      candles.each { |c| series.add_candle(c) }
      allow(instrument).to receive(:candles).with(interval: '5').and_return(series)

      events = described_class.record!(instrument: instrument, interval: '5')

      swing_high_events = events.select { |e| e.event_type == 'swing_high' }
      expect(swing_high_events).not_to be_empty
      expect(swing_high_events.first.payload['price']).to eq(120.0)
      expect(swing_high_events.first.correlation_id).to eq('SMC-STRUCT-NIFTY-5')
      expect(swing_high_events.first.stream).to eq('SMC-STRUCTURE')
    end

    it 'does not re-emit a swing_high already persisted for the same correlation_id' do
      series = build(:candle_series, :five_minute)
      candles = [
        build(:candle, high: 100, low: 90, close: 95),
        build(:candle, high: 101, low: 91, close: 96),
        build(:candle, high: 102, low: 92, close: 97),
        build(:candle, high: 120, low: 100, close: 110),
        build(:candle, high: 108, low: 95, close: 97),
        build(:candle, high: 106, low: 93, close: 96),
        build(:candle, high: 104, low: 91, close: 95)
      ]
      candles.each { |c| series.add_candle(c) }
      allow(instrument).to receive(:candles).with(interval: '5').and_return(series)

      first_run = described_class.record!(instrument: instrument, interval: '5')
      second_run = described_class.record!(instrument: instrument, interval: '5')

      first_swing_highs = first_run.select { |e| e.event_type == 'swing_high' }
      second_swing_highs = second_run.select { |e| e.event_type == 'swing_high' }
      expect(first_swing_highs).not_to be_empty
      expect(second_swing_highs).to be_empty
    end

    it 'persists a bos event when a break of structure occurs' do
      series = build(:candle_series, :five_minute)
      # lookback=3 default: detect_bos_history only considers indices >= lookback,
      # and only counts a swing toward a given index i if swing[:index]+lookback<=i.
      # With swings pinned at index 0 (high) and index 1 (low), both become eligible
      # by index 4 (5 candles total, satisfying MIN_CANDLES).
      candles = [
        build(:candle, high: 100, low: 90, close: 95),  # swing high (mocked)
        build(:candle, high: 98, low: 85, close: 88),   # swing low (mocked)
        build(:candle, high: 97, low: 86, close: 90),
        build(:candle, high: 99, low: 87, close: 91),
        build(:candle, high: 110, low: 88, close: 105)  # closes above swing high -> BOS
      ]
      candles.each { |c| series.add_candle(c) }
      allow(instrument).to receive(:candles).with(interval: '5').and_return(series)
      allow(series).to receive(:swing_high?) { |i| i == 0 }
      allow(series).to receive(:swing_low?) { |i| i == 1 }

      events = described_class.record!(instrument: instrument, interval: '5')
      bos_events = events.select { |e| e.event_type == 'bos' }

      expect(bos_events).not_to be_empty
      expect(bos_events.first.payload['type']).to eq('bullish')
    end
  end
end
