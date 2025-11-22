# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Indicators::Calculator, type: :service do
  let(:candle_series) { build(:candle_series, :with_candles) }
  let(:calculator) { described_class.new(candle_series) }

  describe '#initialize' do
    it 'initializes with a candle series' do
      expect(calculator.instance_variable_get(:@series)).to eq(candle_series)
    end
  end

  describe '#rsi' do
    before do
      allow(candle_series).to receive(:rsi).with(14).and_return(65.5)
    end

    it 'delegates to CandleSeries#rsi' do
      expect(calculator.rsi(14)).to eq(65.5)
      expect(candle_series).to have_received(:rsi).with(14)
    end

    it 'uses default period of 14' do
      allow(candle_series).to receive(:rsi).with(14).and_return(65.5)
      calculator.rsi
      expect(candle_series).to have_received(:rsi).with(14)
    end

    it 'accepts custom period' do
      allow(candle_series).to receive(:rsi).with(10).and_return(70.0)
      expect(calculator.rsi(10)).to eq(70.0)
      expect(candle_series).to have_received(:rsi).with(10)
    end
  end

  describe '#macd' do
    before do
      allow(candle_series).to receive(:macd).with(12, 26, 9).and_return([1.5, 1.2, 0.3])
    end

    it 'delegates to CandleSeries#macd with default parameters' do
      result = calculator.macd
      expect(result).to eq([1.5, 1.2, 0.3])
      expect(candle_series).to have_received(:macd).with(12, 26, 9)
    end

    it 'accepts custom parameters' do
      allow(candle_series).to receive(:macd).with(10, 20, 5).and_return([1.0, 0.8, 0.2])
      result = calculator.macd(10, 20, 5)
      expect(result).to eq([1.0, 0.8, 0.2])
      expect(candle_series).to have_received(:macd).with(10, 20, 5)
    end
  end

  describe '#adx' do
    before do
      allow(candle_series).to receive(:adx).with(14).and_return(25.5)
    end

    it 'delegates to CandleSeries#adx' do
      expect(calculator.adx(14)).to eq(25.5)
      expect(candle_series).to have_received(:adx).with(14)
    end

    it 'uses default period of 14' do
      allow(candle_series).to receive(:adx).with(14).and_return(25.5)
      calculator.adx
      expect(candle_series).to have_received(:adx).with(14)
    end

    it 'accepts custom period' do
      allow(candle_series).to receive(:adx).with(10).and_return(30.0)
      expect(calculator.adx(10)).to eq(30.0)
      expect(candle_series).to have_received(:adx).with(10)
    end
  end

  describe '#bullish_signal?' do
    context 'when all conditions are met' do
      before do
        allow(candle_series).to receive(:rsi).with(14).and_return(25.0) # RSI < 30
        allow(candle_series).to receive(:adx).with(14).and_return(25.0) # ADX > 20
        allow(candle_series).to receive(:closes).and_return([25_000, 25_050, 25_100])
      end

      it 'returns true' do
        expect(calculator.bullish_signal?).to be true
      end
    end

    context 'when RSI is not oversold' do
      before do
        allow(candle_series).to receive(:rsi).with(14).and_return(50.0) # RSI >= 30
        allow(candle_series).to receive(:adx).with(14).and_return(25.0)
        allow(candle_series).to receive(:closes).and_return([25_000, 25_050, 25_100])
      end

      it 'returns false' do
        expect(calculator.bullish_signal?).to be false
      end
    end

    context 'when ADX is weak' do
      before do
        allow(candle_series).to receive(:rsi).with(14).and_return(25.0)
        allow(candle_series).to receive(:adx).with(14).and_return(15.0) # ADX <= 20
        allow(candle_series).to receive(:closes).and_return([25_000, 25_050, 25_100])
      end

      it 'returns false' do
        expect(calculator.bullish_signal?).to be false
      end
    end

    context 'when price is not rising' do
      before do
        allow(candle_series).to receive(:rsi).with(14).and_return(25.0)
        allow(candle_series).to receive(:adx).with(14).and_return(25.0)
        allow(candle_series).to receive(:closes).and_return([25_000, 24_950, 24_900]) # Falling
      end

      it 'returns false' do
        expect(calculator.bullish_signal?).to be false
      end
    end
  end

  describe '#bearish_signal?' do
    context 'when all conditions are met' do
      before do
        allow(candle_series).to receive(:rsi).with(14).and_return(75.0) # RSI > 70
        allow(candle_series).to receive(:adx).with(14).and_return(25.0) # ADX > 20
        allow(candle_series).to receive(:closes).and_return([25_000, 24_950, 24_900]) # Falling
      end

      it 'returns true' do
        expect(calculator.bearish_signal?).to be true
      end
    end

    context 'when RSI is not overbought' do
      before do
        allow(candle_series).to receive(:rsi).with(14).and_return(50.0) # RSI <= 70
        allow(candle_series).to receive(:adx).with(14).and_return(25.0)
        allow(candle_series).to receive(:closes).and_return([25_000, 24_950, 24_900])
      end

      it 'returns false' do
        expect(calculator.bearish_signal?).to be false
      end
    end

    context 'when ADX is weak' do
      before do
        allow(candle_series).to receive(:rsi).with(14).and_return(75.0)
        allow(candle_series).to receive(:adx).with(14).and_return(15.0) # ADX <= 20
        allow(candle_series).to receive(:closes).and_return([25_000, 24_950, 24_900])
      end

      it 'returns false' do
        expect(calculator.bearish_signal?).to be false
      end
    end

    context 'when price is not falling' do
      before do
        allow(candle_series).to receive(:rsi).with(14).and_return(75.0)
        allow(candle_series).to receive(:adx).with(14).and_return(25.0)
        allow(candle_series).to receive(:closes).and_return([25_000, 25_050, 25_100]) # Rising
      end

      it 'returns false' do
        expect(calculator.bearish_signal?).to be false
      end
    end
  end

  describe 'integration with CandleSeries' do
    let(:series) { build(:candle_series, :with_candles) }
    let(:calc) { described_class.new(series) }

    it 'calculates RSI using CandleSeries method' do
      rsi_value = calc.rsi(14)
      expect(rsi_value).to be_a(Numeric).or be_nil
    end

    it 'calculates MACD using CandleSeries method' do
      macd_result = calc.macd
      expect(macd_result).to be_an(Array).or be_nil
    end

    it 'calculates ADX using CandleSeries method' do
      adx_value = calc.adx(14)
      expect(adx_value).to be_a(Numeric).or be_nil
    end
  end
end

