# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Avrz::Detector do
  describe '#rejection?' do
    it 'returns true for a high-volume rejection candle' do
      series = build(:candle_series, :five_minute)

      10.times do |i|
        series.add_candle(
          build(
            :candle,
            timestamp: (20 - i).minutes.ago,
            open: 100,
            high: 102,
            low: 99,
            close: 101,
            volume: 100
          )
        )
      end

      # Long lower wick + bullish close + high volume
      series.add_candle(
        build(
          :candle,
          timestamp: 1.minute.ago,
          open: 100,
          high: 101,
          low: 90,
          close: 100.5,
          volume: 1000
        )
      )

      detector = described_class.new(series, lookback: 10, min_wick_ratio: 1.5, min_vol_multiplier: 2.0)
      expect(detector.rejection?).to be(true)
    end
  end
end

