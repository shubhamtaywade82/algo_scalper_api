# frozen_string_literal: true

require 'spec_helper'
require_relative '../../src/market_data/candle_aggregator'

RSpec.describe MarketData::CandleAggregator do
  let(:aggregator) { described_class.new(interval_minutes: 1) }

  describe '#process_tick' do
    it 'aggregates ticks into a single candle' do
      closed_candles = []
      aggregator.on_candle_close { |c| closed_candles << c }

      t1 = Time.parse('2024-01-01 10:00:05 +0530')
      t2 = Time.parse('2024-01-01 10:00:30 +0530')
      t3 = Time.parse('2024-01-01 10:01:05 +0530') # New minute

      aggregator.process_tick(OpenStruct.new(timestamp: t1, last_price: 100, last_quantity: 10, symbol: 'NIFTY'))
      aggregator.process_tick(OpenStruct.new(timestamp: t2, last_price: 105, last_quantity: 5, symbol: 'NIFTY'))
      
      expect(aggregator.current_candle[:high]).to eq(105)
      expect(aggregator.current_candle[:volume]).to eq(15)

      aggregator.process_tick(OpenStruct.new(timestamp: t3, last_price: 102, last_quantity: 20, symbol: 'NIFTY'))

      expect(closed_candles.size).to eq(1)
      expect(closed_candles.first.close).to eq(105)
      expect(closed_candles.first.volume).to eq(15)
      expect(aggregator.current_candle[:open]).to eq(102)
    end
  end
end
