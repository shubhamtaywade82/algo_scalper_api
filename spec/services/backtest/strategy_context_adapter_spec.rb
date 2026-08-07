# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Backtest::StrategyContextAdapter do
  let(:base_ts) { Time.zone.parse('2026-07-06 09:15:00') }

  def candle(offset_minutes, close:)
    Candle.new(
      timestamp: base_ts + offset_minutes.minutes,
      open: close, high: close, low: close, close: close, volume: 100
    )
  end

  let(:candles) { (0..5).map { |i| candle(i, close: 100 + i) } } # 09:15..09:20
  let(:series_1m) do
    CandleSeries.new(symbol: 'NIFTY', interval: '1').tap do |s|
      candles.each { |c| s.add_candle(c) }
    end
  end
  let(:adapter) { described_class.new(series_1m: series_1m, symbol: 'NIFTY') }

  describe '#build' do
    it 'excludes the candle exactly at the cutoff timestamp (exclusive upper bound)' do
      cutoff = base_ts + 5.minutes # 09:20 — the timestamp of the last seeded candle

      context = adapter.build(cutoff: cutoff, params: {})
      series = context.candles.call('1m')

      expect(series.candles.map(&:timestamp)).not_to include(cutoff)
      expect(series.candles.last.timestamp).to eq(base_ts + 4.minutes)
    end

    it 'includes candles strictly before the cutoff' do
      cutoff = base_ts + 5.minutes

      context = adapter.build(cutoff: cutoff, params: {})
      series = context.candles.call('1m')

      expect(series.candles.size).to eq(5)
    end

    it 'resamples to the requested timeframe' do
      cutoff = base_ts + 5.minutes

      context = adapter.build(cutoff: cutoff, params: {})
      series = context.candles.call('3m')

      expect(series.candles.size).to eq(2)
      expect(series.candles.first.timestamp).to eq(base_ts)
    end

    it 'drops candles older than the trailing lookback window' do
      old_candle = Candle.new(
        timestamp: base_ts - 7.hours, open: 50, high: 50, low: 50, close: 50, volume: 10
      )
      series_with_old = CandleSeries.new(symbol: 'NIFTY', interval: '1').tap do |s|
        s.add_candle(old_candle)
        candles.each { |c| s.add_candle(c) }
      end
      adapter_with_old = described_class.new(series_1m: series_with_old, symbol: 'NIFTY')

      context = adapter_with_old.build(cutoff: base_ts + 5.minutes, params: {})
      series = context.candles.call('1m')

      expect(series.candles.map(&:timestamp)).not_to include(old_candle.timestamp)
    end

    it 'exposes the cutoff as the context clock' do
      cutoff = base_ts + 5.minutes
      context = adapter.build(cutoff: cutoff, params: {})

      expect(context.clock.call).to eq(cutoff)
    end

    it 'passes params through unchanged' do
      context = adapter.build(cutoff: base_ts + 5.minutes, params: { rsi_period: 14 })

      expect(context.params).to eq(rsi_period: 14)
    end

    it 'leaves indicators, session, and position nil for v1' do
      context = adapter.build(cutoff: base_ts + 5.minutes, params: {})

      expect(context.indicators).to be_nil
      expect(context.session).to be_nil
      expect(context.position).to be_nil
    end
  end
end
