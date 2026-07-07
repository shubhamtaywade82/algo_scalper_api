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

    it 'links a choch event to the most recent bos event as its parent' do
      # Smc::Detectors::Structure#choch? is structurally unreachable via real candle
      # data (its bullish->bearish branch requires close < last_swing_low, but #trend
      # calls #bos? first, which already intercepts that exact condition and returns
      # :bearish directly -- current_trend can never be :bullish when that check holds).
      # Pre-existing bug in the detector, out of scope here. Stub it at the boundary to
      # test StructureEventRecorder's own choch-wiring/parent-linking logic instead.
      series = build(:candle_series, :five_minute)
      candles = [
        build(:candle, high: 100, low: 90, close: 95),
        build(:candle, high: 98, low: 85, close: 88),
        build(:candle, high: 97, low: 86, close: 90),
        build(:candle, high: 99, low: 87, close: 91),
        build(:candle, high: 110, low: 88, close: 105) # closes above swing high -> BOS
      ]
      candles.each { |c| series.add_candle(c) }
      allow(instrument).to receive(:candles).with(interval: '5').and_return(series)
      allow(series).to receive(:swing_high?) { |i| i == 0 }
      allow(series).to receive(:swing_low?) { |i| i == 1 }
      allow_any_instance_of(Smc::Detectors::Structure).to receive(:choch?) # rubocop:disable RSpec/AnyInstance
        .and_return({ type: :bearish, price: 82.0, index: 4, semantic: :choch })

      events = described_class.record!(instrument: instrument, interval: '5')
      bos_event = events.find { |e| e.event_type == 'bos' }
      choch_event = events.find { |e| e.event_type == 'choch' }

      expect(bos_event).not_to be_nil
      expect(choch_event).not_to be_nil
      expect(choch_event.payload['parent_event_id']).to eq(bos_event.id)
    end

    it 'persists an fvg_created event for an active fair value gap' do
      series = build(:candle_series, :five_minute)
      series.add_candle(build(:candle, open: 100, high: 102, low: 99, close: 101))
      series.add_candle(build(:candle, open: 101, high: 105, low: 100.5, close: 104))
      series.add_candle(build(:candle, open: 104, high: 106, low: 103, close: 105))
      series.add_candle(build(:candle, open: 105, high: 107, low: 104, close: 106)) # stays above gap[:to]=103, no mitigation
      series.add_candle(build(:candle, open: 106, high: 108, low: 105, close: 107))
      allow(instrument).to receive(:candles).with(interval: '5').and_return(series)
      allow(series).to receive(:atr).with(20).and_return(1.0)

      events = described_class.record!(instrument: instrument, interval: '5')
      fvg_events = events.select { |e| e.event_type == 'fvg_created' }

      expect(fvg_events.size).to eq(1)
      expect(fvg_events.first.payload['type']).to eq('bullish')
      expect(fvg_events.first.payload['from']).to eq(102.0)
      expect(fvg_events.first.payload['to']).to eq(103.0)
    end

    it 'persists an order_block_formed event for an active order block' do
      series = build(:candle_series, :five_minute)
      series.add_candle(build(:candle, open: 105, high: 106, low: 100, close: 101)) # bearish
      series.add_candle(build(:candle, open: 101, high: 112, low: 100.5, close: 111)) # bullish displacement, closes above a.high
      series.add_candle(build(:candle, open: 111, high: 113, low: 109, close: 112))
      series.add_candle(build(:candle, open: 112, high: 114, low: 110, close: 113))
      series.add_candle(build(:candle, open: 113, high: 115, low: 111, close: 114)) # MIN_CANDLES, stays above block low=100
      allow(instrument).to receive(:candles).with(interval: '5').and_return(series)
      allow(series).to receive(:atr).with(20).and_return(1.0)

      events = described_class.record!(instrument: instrument, interval: '5')
      ob_events = events.select { |e| e.event_type == 'order_block_formed' }

      expect(ob_events.size).to eq(1)
      expect(ob_events.first.payload['bias']).to eq('bullish')
      expect(ob_events.first.payload['high']).to eq(106.0)
      expect(ob_events.first.payload['low']).to eq(100.0)
    end
  end
end
