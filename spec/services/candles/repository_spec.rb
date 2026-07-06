# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Candles::Repository do
  describe '.series' do
    let(:instrument_key) { 'NIFTY' }
    let(:from) { Time.zone.parse('2026-07-06 09:15') }
    let(:to)   { Time.zone.parse('2026-07-06 09:20') }

    before do
      ts_base = Time.zone.parse('2026-07-06 09:15')
      [
        { instrument_key: 'NIFTY', timeframe: '1m', ts: ts_base,           open: 100, high: 110, low: 99,  close: 105, volume: 1000, oi: 0 },
        { instrument_key: 'NIFTY', timeframe: '1m', ts: ts_base + 60,       open: 105, high: 108, low: 102, close: 107, volume: 800,  oi: 0 },
        { instrument_key: 'NIFTY', timeframe: '1m', ts: ts_base + 120,      open: 107, high: 115, low: 106, close: 114, volume: 1200, oi: 0 },
        { instrument_key: 'NIFTY', timeframe: '1m', ts: ts_base + 180,      open: 114, high: 116, low: 110, close: 112, volume: 900,  oi: 0 },
        { instrument_key: 'NIFTY', timeframe: '1m', ts: ts_base + 240,      open: 112, high: 113, low: 108, close: 109, volume: 600,  oi: 0 }
      ].each { |attrs| Candles::Record.create!(exchange_segment: 'IDX_I', security_id: '13', **attrs) }
    end

    it 'returns 1m candles for the base timeframe' do
      result = described_class.series(instrument_key: instrument_key, from: from, to: to)
      expect(result.size).to eq(5)
      expect(result.first).to match(ts: an_instance_of(ActiveSupport::TimeWithZone), open: 100.0, high: 110.0, low: 99.0, close: 105.0, volume: 1000, oi: 0)
      expect(result.last).to match(hash_including(open: 112.0, close: 109.0))
    end

    it 'derives higher timeframes by bucketing' do
      result = described_class.series(instrument_key: instrument_key, timeframe: '5m', from: from, to: to)
      expect(result.size).to eq(1)
      expect(result.first).to match(hash_including(open: 100.0, high: 116.0, low: 99.0, close: 109.0, volume: 4500))
    end

    it 'raises ArgumentError for unsupported timeframes' do
      expect {
        described_class.series(instrument_key: instrument_key, timeframe: '1h', from: from, to: to)
      }.to raise_error(ArgumentError, /Unsupported timeframe/)
    end

    it 'returns empty array when no candles match' do
      result = described_class.series(instrument_key: 'UNKNOWN', from: from, to: to)
      expect(result).to eq([])
    end
  end
end
