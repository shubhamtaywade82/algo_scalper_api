# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Smc::Detectors::Liquidity do
  def stub_structure_swings(series, swings)
    structure = instance_double(Smc::Detectors::Structure, swings: swings)
    allow(Smc::Detectors::Structure).to receive(:new).with(series).and_return(structure)
  end

  def series_with_last_candle(high:, close:, low:)
    last = instance_double(Candle, high: high, close: close, low: low)
    series = instance_double(CandleSeries)
    allow(series).to receive(:candles).and_return([last])
    series
  end

  describe '#buy_side_taken?' do
    it 'returns true when last candle sweeps above swing high then closes below' do
      series = series_with_last_candle(high: 102.0, close: 99.0, low: 98.0)
      stub_structure_swings(series, [{ type: :high, price: 100.0, index: 0 }])

      detector = described_class.new(series)
      expect(detector.buy_side_taken?).to be(true)
    end

    it 'returns false when buy-side sweep pattern is absent' do
      series = series_with_last_candle(high: 101.0, close: 101.0, low: 99.0)
      stub_structure_swings(series, [{ type: :high, price: 100.0, index: 0 }])

      detector = described_class.new(series)
      expect(detector.buy_side_taken?).to be(false)
    end

    it 'raises when series is nil' do
      expect { described_class.new(nil).buy_side_taken? }.to raise_error(NoMethodError)
    end
  end

  describe '#sell_side_taken?' do
    it 'returns true when last candle sweeps below swing low then closes above' do
      series = series_with_last_candle(high: 101.0, close: 101.0, low: 99.0)
      stub_structure_swings(series, [{ type: :low, price: 100.0, index: 0 }])

      detector = described_class.new(series)
      expect(detector.sell_side_taken?).to be(true)
    end

    it 'returns false when sell-side sweep pattern is absent' do
      series = series_with_last_candle(high: 101.0, close: 99.0, low: 100.5)
      stub_structure_swings(series, [{ type: :low, price: 100.0, index: 0 }])

      detector = described_class.new(series)
      expect(detector.sell_side_taken?).to be(false)
    end

    it 'raises when series is nil' do
      expect { described_class.new(nil).sell_side_taken? }.to raise_error(NoMethodError)
    end
  end

  describe '#to_h' do
    it 'serializes liquidity state' do
      series = series_with_last_candle(high: 102.0, close: 99.0, low: 98.0)
      stub_structure_swings(
        series,
        [
          { type: :high, price: 100.0, index: 0 },
          { type: :high, price: 100.2, index: 1 },
          { type: :low, price: 95.0, index: 2 },
          { type: :low, price: 95.1, index: 3 }
        ]
      )

      detector = described_class.new(series)
      result = detector.to_h

      expect(result).to include(
        buy_side_taken: true,
        sell_side_taken: false,
        equal_highs: true,
        equal_lows: true
      )
    end
  end
end
