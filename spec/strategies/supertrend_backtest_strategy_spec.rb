# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SupertrendBacktestStrategy do
  # Rising first half, falling second half: the final trend of the WHOLE series
  # is bearish, but the trend at any bar in the first half is bullish. The
  # pre-fix implementation computed Supertrend over the full series for every
  # per-bar call, so bar 20 (plainly in a rise) reported the final bearish
  # trend — hindsight that invalidated every EquityBacktestJob metric
  # (lookahead bias, review P1).
  let(:series) do
    s = CandleSeries.new(symbol: 'NIFTY', interval: '5', max_candles: 200)
    base = Time.zone.parse('2026-07-06 09:15:00')

    60.times do |i|
      close = i < 30 ? 24_000.0 + (i * 20.0) : 24_600.0 - ((i - 30) * 20.0)
      s.add_candle(Candle.new(
        timestamp: base + (i * 5.minutes),
        open: close - 5.0, high: close + 15.0, low: close - 15.0,
        close: close, volume: 0
      ))
    end
    s
  end

  let(:strategy) { described_class.new(series: series) }

  describe '#generate_signal point-in-time contract' do
    it 'reports the trend as of bar 20, not the final trend of the whole series' do
      signal = strategy.generate_signal(20)

      expect(signal).not_to be_nil
      expect(signal[:direction]).to eq(:buy)
      expect(signal[:price]).to eq(series.candles[20].close)
    end

    it 'reports the bearish trend late in the series' do
      signal = strategy.generate_signal(59)

      expect(signal).not_to be_nil
      expect(signal[:direction]).to eq(:sell)
    end

    it 'equals the signal of the independently truncated series' do
      15.step(59, 5) do |i|
        truncated = CandleSeries.new(symbol: 'NIFTY', interval: '5', max_candles: [i + 1, 1].max)
        series.candles[0..i].each { |c| truncated.add_candle(c) }
        expected = described_class.new(series: truncated).generate_signal

        expect(strategy.generate_signal(i)).to eq(expected)
      end
    end

    it 'keeps whole-series semantics for a nil index (one-shot callers)' do
      expect(strategy.generate_signal[:direction]).to eq(:sell)
    end

    it 'returns nil during warmup when Supertrend has no valid line yet' do
      expect(strategy.generate_signal(0)).to be_nil
    end
  end
end
