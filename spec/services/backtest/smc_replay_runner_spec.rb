# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Backtest::SmcReplayRunner do
  let(:base_time) { Time.zone.parse('2025-06-10 09:15:00') }

  let(:ohlc_5m) do
    Array.new(40) do |i|
      t = base_time + (i * 5).minutes
      o = 25_000.0 + (i * 2)
      { timestamp: t, open: o, high: o + 30, low: o - 10, close: o + 20, volume: 1_000_000 + i }
    end
  end

  let(:ohlc_15m) do
    Array.new(14) do |i|
      t = base_time + (i * 15).minutes
      o = 25_000.0 + (i * 6)
      { timestamp: t, open: o, high: o + 40, low: o - 15, close: o + 25, volume: 2_000_000 }
    end
  end

  let(:ohlc_60m) do
    Array.new(5) do |i|
      t = base_time + (i * 60).minutes
      o = 25_000.0 + (i * 10)
      { timestamp: t, open: o, high: o + 50, low: o - 20, close: o + 30, volume: 5_000_000 }
    end
  end

  let!(:instrument) { create(:instrument, :nifty_index) }

  describe '#call' do
    # rubocop:disable RSpec/MultipleExpectations -- single result hash contract
    it 'returns spot_summary and no error for replayable data' do
      index_scope = instance_double(ActiveRecord::Relation)
      allow(Instrument).to receive(:segment_index).and_return(index_scope)
      allow(index_scope).to receive(:find_by).with(symbol_name: 'NIFTY').and_return(instrument)
      allow(instrument).to receive(:intraday_ohlc).and_return(ohlc_5m, ohlc_15m, ohlc_60m)

      result = described_class.new(
        symbol: 'NIFTY',
        days_back: 5,
        min_bars: 10,
        include_permission: true,
        simulate_options: false
      ).call

      expect(result[:error]).to be_nil
      expect(result[:bars]).to eq(40)
      expect(result[:spot_summary]).to be_a(Hash)
      expect(result[:spot_summary]).to have_key(:count)
      expect(result[:options_summary][:total_trades]).to eq(0)
    end
    # rubocop:enable RSpec/MultipleExpectations

    it 'returns error when instrument is missing' do
      result = described_class.new(symbol: 'UNKNOWN_INDEX_XYZ').call

      expect(result[:error]).to eq('Instrument not found')
    end
  end
end
