# frozen_string_literal: true

require 'rails_helper'

RSpec.describe MarketRegimeDetector do
  subject { described_class.new(series) }

  let(:symbol) { 'BANKNIFTY' }
  let(:interval) { '5' }
  let(:series) { CandleSeries.new(symbol: symbol, interval: interval) }

  describe '#detect' do
    context 'when there is insufficient data' do
      it 'returns INSUFFICIENT_DATA' do
        result = subject.detect
        expect(result[:regime]).to eq('INSUFFICIENT_DATA')
      end
    end

    context 'with sufficient data' do
      before do
        # Create 20 candles to meet the MIN_CANDLES requirement
        base_time = Time.current.beginning_of_day
        base_price = 45_000.0

        25.times do |i|
          # A slight uptrend to populate data
          price = base_price + (i * 10)
          series.add_candle(Candle.new(
            timestamp: base_time + (i * 5).minutes,
            open: price - 5,
            high: price + 10,
            low: price - 10,
            close: price,
            volume: 1000
          ))
        end
      end

      it 'calculates regime successfully' do
        # We need to stub the indicator calculators to tightly control the test conditions
        # since we just added generic dummy data
        allow(series).to receive_messages(adx: 70.0, atr: 50.0, bollinger_bands: { upper: 45_000, lower: 44_000, middle: 44_500 })

        result = subject.detect
        expect(result[:regime]).to include('TRENDING')
        expect(result[:confidence]).to eq(70.0)
        expect(result[:metrics][:adx_value]).to eq(70.0)
        expect(result[:metrics][:bb_breakout]).to be(true) # Last close is > 45000
      end

      it 'classifies as RANGING when ADX and volatility are low' do
        allow(series).to receive_messages(adx: 20.0, atr: 10.0, bollinger_bands: { upper: 55_000, lower: 34_000, middle: 44_500 }) # No breakout

        result = subject.detect
        expect(result[:regime]).to eq('RANGING')
        expect(result[:confidence]).to eq(80.0) # 100 - ADX
      end
    end
  end
end
