# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Smc::Confluence::CandleRows do
  describe '.from_series' do
    it 'returns empty array for nil' do
      expect(described_class.from_series(nil)).to eq([])
    end

    it 'maps Candle objects to engine hash rows' do
      series = CandleSeries.new(symbol: 'X', interval: '5')
      t = Time.zone.parse('2024-06-01 10:00:00 UTC')
      series.add_candle(Candle.new(timestamp: t, open: 1, high: 2, low: 0.5, close: 1.5, volume: 100))

      rows = described_class.from_series(series)
      expect(rows.size).to eq(1)
      expect(rows.first[:timestamp]).to eq(t.to_i)
      expect(rows.first[:open]).to eq(1.0)
      expect(rows.first[:volume]).to eq(100.0)
    end
  end
end
