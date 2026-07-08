# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Candles::Persister do
  let(:index_instrument) { build_stubbed(:instrument, :nifty_index) }
  let(:strike_instrument) { build_stubbed(:instrument, security_id: '52175', symbol_name: 'NIFTY24500CE', segment: 'derivatives') }

  let(:candles) do
    [
      { 'timestamp' => Time.utc(2026, 7, 6, 9, 15, 0), 'open' => 25_000.0, 'high' => 25_050.0,
        'low' => 24_980.0, 'close' => 25_020.0, 'volume' => 1_000, 'oi' => 0 }
    ]
  end

  describe '.persistable?' do
    it 'is true for a 1m index candle' do
      expect(described_class.persistable?(index_instrument, 1)).to be true
    end

    it 'is false for a non-1m interval' do
      expect(described_class.persistable?(index_instrument, 5)).to be false
    end

    it 'is false for a non-index instrument' do
      expect(described_class.persistable?(strike_instrument, 1)).to be false
    end

    it 'is false for a nil instrument' do
      expect(described_class.persistable?(nil, 1)).to be false
    end
  end

  describe '.enqueue' do
    it 'enqueues Candles::PersistCandlesJob with normalized string-keyed candles for a persistable instrument' do
      expect(Candles::PersistCandlesJob).to receive(:perform_later).with(
        instrument_key: 'NIFTY',
        exchange_segment: 'IDX_I',
        security_id: '13',
        timeframe: '1m',
        source: 'live',
        candles: [
          { 'timestamp' => '2026-07-06T09:15:00.000Z', 'open' => 25_000.0, 'high' => 25_050.0,
            'low' => 24_980.0, 'close' => 25_020.0, 'volume' => 1_000, 'oi' => 0 }
        ]
      )

      described_class.enqueue(instrument: index_instrument, interval: 1, candles: candles)
    end

    it 'does not enqueue for a non-persistable instrument/interval combo' do
      expect(Candles::PersistCandlesJob).not_to receive(:perform_later)

      described_class.enqueue(instrument: strike_instrument, interval: 1, candles: candles)
    end

    it 'does not enqueue when candles is blank' do
      expect(Candles::PersistCandlesJob).not_to receive(:perform_later)

      described_class.enqueue(instrument: index_instrument, interval: 1, candles: [])
    end
  end
end
