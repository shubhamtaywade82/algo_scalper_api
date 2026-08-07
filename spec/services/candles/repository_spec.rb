# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Candles::Repository do
  let(:base_ts) { Time.zone.parse('2026-07-06 09:15:00') }

  def seed_minute(offset_minutes, open:, high:, low:, close:, volume: 100)
    Candles::Record.create!(
      instrument_key: 'NIFTY', exchange_segment: 'IDX_I', security_id: '13',
      timeframe: '1m', ts: base_ts + offset_minutes.minutes,
      open: open, high: high, low: low, close: close, volume: volume, source: 'live'
    )
  end

  describe '.series with the base 1m timeframe' do
    before do
      seed_minute(0, open: 25_000, high: 25_010, low: 24_995, close: 25_005)
      seed_minute(1, open: 25_005, high: 25_020, low: 25_000, close: 25_015)
    end

    it 'returns ordered 1m bars within the range' do
      result = described_class.series(instrument_key: 'NIFTY', timeframe: '1m', from: base_ts, to: base_ts + 5.minutes)

      expect(result).to be_a(CandleSeries)
      expect(result.candles.size).to eq(2)
      expect(result.candles.map(&:close)).to eq([25_005.0, 25_015.0])
    end

    it 'excludes bars outside the range' do
      result = described_class.series(instrument_key: 'NIFTY', timeframe: '1m', from: base_ts + 2.minutes, to: base_ts + 5.minutes)
      expect(result.candles).to be_empty
    end
  end

  describe '.series with a derived timeframe' do
    before do
      seed_minute(0, open: 100, high: 110, low: 95, close: 105)
      seed_minute(1, open: 105, high: 120, low: 100, close: 115)
      seed_minute(2, open: 115, high: 118, low: 108, close: 112)
      # second 3m bucket starts here (base_ts + 3 .. base_ts + 5)
      seed_minute(3, open: 112, high: 130, low: 110, close: 128)
      seed_minute(4, open: 128, high: 135, low: 125, close: 130)
    end

    it 'derives 3m bars via OHLC rollup' do
      result = described_class.series(instrument_key: 'NIFTY', timeframe: '3m', from: base_ts, to: base_ts + 5.minutes)

      expect(result.candles.size).to eq(2)

      first = result.candles.first
      expect(first.timestamp).to eq(base_ts)
      expect(first.open).to eq(100.0)
      expect(first.high).to eq(120.0)
      expect(first.low).to eq(95.0)
      expect(first.close).to eq(112.0)
      expect(first.volume).to eq(300)

      second = result.candles.second
      expect(second.open).to eq(112.0)
      expect(second.high).to eq(135.0)
      expect(second.low).to eq(110.0)
      expect(second.close).to eq(130.0)
    end
  end

  describe '.series with an unsupported timeframe' do
    it 'raises ArgumentError' do
      expect do
        described_class.series(instrument_key: 'NIFTY', timeframe: 'bogus', from: base_ts, to: base_ts + 1.minute)
      end.to raise_error(ArgumentError, /Unsupported timeframe/)
    end

    it 'raises ArgumentError for a zero-minute timeframe instead of dividing by zero' do
      seed_minute(0, open: 100, high: 105, low: 95, close: 100)

      expect do
        described_class.series(instrument_key: 'NIFTY', timeframe: '0m', from: base_ts, to: base_ts + 1.minute)
      end.to raise_error(ArgumentError, /Unsupported timeframe/)
    end
  end

  describe '.series bucket alignment across an hour boundary' do
    let(:hour_ts) { Time.zone.parse('2026-07-06 09:00:00') }

    before do
      # Seed 1m bars straddling the 09:00 IST hour boundary so that
      # epoch-based bucketing (misaligned by 30 minutes vs IST) and
      # local-midnight-based bucketing disagree on the 60m bucket start.
      Candles::Record.create!(
        instrument_key: 'NIFTY', exchange_segment: 'IDX_I', security_id: '13',
        timeframe: '1m', ts: hour_ts - 1.minute,
        open: 200, high: 205, low: 195, close: 200, volume: 100, source: 'live'
      )
      Candles::Record.create!(
        instrument_key: 'NIFTY', exchange_segment: 'IDX_I', security_id: '13',
        timeframe: '1m', ts: hour_ts,
        open: 200, high: 210, low: 198, close: 208, volume: 100, source: 'live'
      )
    end

    it 'aligns 60m buckets to local (IST) hour boundaries, not epoch-based ones' do
      result = described_class.series(
        instrument_key: 'NIFTY', timeframe: '60m', from: hour_ts - 5.minutes, to: hour_ts + 5.minutes
      )

      result.candles.each do |bar|
        local = bar.timestamp.in_time_zone
        expect(local.min).to eq(0), "expected bucket ts #{local} to fall on a local hour boundary"
      end
    end
  end

  describe '.series when no data exists' do
    it 'returns an empty series' do
      result = described_class.series(instrument_key: 'BANKNIFTY', timeframe: '5m', from: base_ts, to: base_ts + 1.hour)
      expect(result.candles).to eq([])
    end
  end

  describe '.rollup_candles' do
    def candle(offset_minutes, open:, high:, low:, close:, volume: 100)
      Candle.new(
        timestamp: base_ts + offset_minutes.minutes,
        open: open, high: high, low: low, close: close, volume: volume
      )
    end

    it 'resamples an in-memory Array<Candle> without touching the Record table' do
      candles = [
        candle(0, open: 100, high: 110, low: 95, close: 105),
        candle(1, open: 105, high: 120, low: 100, close: 115),
        candle(2, open: 115, high: 118, low: 108, close: 112)
      ]

      result = described_class.rollup_candles(candles: candles, symbol: 'NIFTY', timeframe: '3m')

      expect(result).to be_a(CandleSeries)
      expect(result.candles.size).to eq(1)
      bar = result.candles.first
      expect(bar.timestamp).to eq(base_ts)
      expect(bar.open).to eq(100.0)
      expect(bar.high).to eq(120.0)
      expect(bar.low).to eq(95.0)
      expect(bar.close).to eq(112.0)
      expect(bar.volume).to eq(300)
      expect(Candles::Record.count).to eq(0)
    end

    it 'passes 1m candles through unchanged when timeframe matches the base timeframe' do
      candles = [candle(0, open: 100, high: 105, low: 95, close: 100)]

      result = described_class.rollup_candles(candles: candles, symbol: 'NIFTY', timeframe: '1m')

      expect(result.candles.size).to eq(1)
      expect(result.candles.first.close).to eq(100.0)
    end
  end
end
