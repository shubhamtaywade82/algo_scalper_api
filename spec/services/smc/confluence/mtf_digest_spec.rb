# frozen_string_literal: true

# rubocop:disable RSpec/MultipleExpectations
require 'rails_helper'

RSpec.describe Smc::Confluence::MtfDigest do
  def candle_row(i, close: 100.0 + i)
    {
      timestamp: i * 300,
      open: close - 0.5,
      high: close + 1.0,
      low: close - 1.0,
      close: close,
      volume: 10.0
    }
  end

  describe '.from_timeframe_candles' do
    it 'returns schema, per-timeframe confluence, and alignment maps' do
      rows = (0...50).map { |i| candle_row(i) }
      payload = described_class.from_timeframe_candles(
        symbol: 'NIFTY',
        timeframe_candles: { '4h' => rows, '1h' => rows, '5m' => rows }
      )

      expect(payload['kind']).to eq('smc_confluence_mtf')
      expect(payload['symbol']).to eq('NIFTY')
      expect(payload['timeframes'].keys.map(&:to_s)).to contain_exactly('4h', '1h', '5m')

      %w[4h 1h 5m].each do |tf|
        block = payload['timeframes'][tf]
        expect(block['candle_count']).to eq(50)
        expect(block['confluence']).to be_a(Hash)
        expect(block['confluence']).to include('long_score', 'short_score', 'choch_bull', 'structure_bias')
        expect(block['last_close']).to be_a(Float)
      end

      align = payload['alignment']
      expect(align['long_signal'].keys.map(&:to_s)).to include('4h', '1h', '5m')
      expect(align['structure_bias']).to be_a(Hash)
      %w[liq_sweep_bull liq_sweep_bear pdh_sweep pdl_sweep].each do |key|
        expect(align).to have_key(key)
        expect(align[key]).to be_a(Hash)
      end
    end

    it 'coerces trendline break flags to booleans inside confluence' do
      rows = (0...30).map { |i| candle_row(i) }
      payload = described_class.from_timeframe_candles(
        symbol: 'BANKNIFTY',
        timeframe_candles: { '5m' => rows }
      )
      br = payload['timeframes']['5m']['confluence']
      expect(br['tl_bear_break']).to be_in([true, false])
      expect(br['tl_bull_break']).to be_in([true, false])
    end
  end
end
# rubocop:enable RSpec/MultipleExpectations
