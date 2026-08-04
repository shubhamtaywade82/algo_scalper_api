# frozen_string_literal: true

require 'rails_helper'

RSpec.describe MarketRegimeDetector do
  let(:symbol) { 'BANKNIFTY' }
  let(:interval) { '5' }
  let(:series) { CandleSeries.new(symbol: symbol, interval: interval) }

  subject { described_class.new(series) }

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
        base_price = 45000.0

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
        allow(series).to receive(:adx).and_return(70.0) # Strong trend
        allow(series).to receive(:atr).and_return(50.0)
        allow(series).to receive(:bollinger_bands).and_return({ upper: 45000, lower: 44000, middle: 44500 })

        result = subject.detect
        expect(result[:regime]).to include('TRENDING')
        expect(result[:confidence]).to eq(70.0)
        expect(result[:metrics][:adx_value]).to eq(70.0)
        expect(result[:metrics][:bb_breakout]).to eq(true) # Last close is > 45000
      end

      it 'classifies as RANGING when ADX and volatility are low' do
        allow(series).to receive(:adx).and_return(20.0) # Weak trend
        allow(series).to receive(:atr).and_return(10.0) # Low volatility
        allow(series).to receive(:bollinger_bands).and_return({ upper: 55000, lower: 34000, middle: 44500 }) # No breakout

        result = subject.detect
        expect(result[:regime]).to eq('RANGING')
        expect(result[:confidence]).to eq(80.0) # 100 - ADX
      end
    end
  end
end
