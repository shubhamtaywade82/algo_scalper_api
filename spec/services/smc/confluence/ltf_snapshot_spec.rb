# frozen_string_literal: true

# rubocop:disable Performance/TimesMap, Lint/AmbiguousOperatorPrecedence
require 'rails_helper'

RSpec.describe Smc::Confluence::LtfSnapshot do
  def build_rows(n)
    n.times.map do |i|
      {
        timestamp: (1_700_000_000 + i * 300),
        open: 100.0 + i * 0.01,
        high: 101.0 + i * 0.01,
        low: 99.0 + i * 0.01,
        close: 100.5 + i * 0.01,
        volume: 1_000.0
      }
    end
  end

  describe '.fetch' do
    it 'returns nil last when fewer than 10 candles' do
      inst = instance_double(Instrument)
      series = CandleSeries.new(symbol: 'N', interval: '5')
      build_rows(5).each { |r| inst_candle_from_row(series, r) }
      allow(inst).to receive(:candles).with(interval: '5').and_return(series)

      snap = described_class.fetch(instrument: inst, signals_cfg: {})
      expect(snap[:last]).to be_nil
    end

    it 'returns summary hash when enough candles' do
      inst = instance_double(Instrument)
      series = CandleSeries.new(symbol: 'N', interval: '5')
      build_rows(120).each { |r| inst_candle_from_row(series, r) }
      allow(inst).to receive(:candles).with(interval: '5').and_return(series)

      snap = described_class.fetch(instrument: inst, signals_cfg: {})
      expect(snap[:last]).to be_a(Smc::Confluence::BarResult)
      expect(snap[:summary]).to be_a(Hash)
      expect(snap[:summary].keys).to include('long_score', 'short_score')
    end
  end

  describe '.gate_passes?' do
    it 'returns true when snap is nil (fail-open)' do
      expect(described_class.gate_passes?(:bullish, nil)).to be(true)
    end

    it 'returns true when last is nil (fail-open)' do
      expect(described_class.gate_passes?(:bullish, { last: nil })).to be(true)
    end
  end

  def inst_candle_from_row(series, row)
    series.add_candle(
      Candle.new(
        timestamp: Time.zone.at(row[:timestamp]),
        open: row[:open],
        high: row[:high],
        low: row[:low],
        close: row[:close],
        volume: row[:volume]
      )
    )
  end
end
# rubocop:enable Performance/TimesMap, Lint/AmbiguousOperatorPrecedence
