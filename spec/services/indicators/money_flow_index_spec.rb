# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Indicators::MoneyFlowIndex do
  describe '#call' do
    context 'with bullish price & volume increasing' do
      subject(:result) { described_class.call(candles) }

      let(:candles) do
        (1..20).map do |i|
          base = 22_000 + (i * 3)
          { high: base + 4, low: base - 2, close: base + 2, volume: 1000 + (i * 50) }
        end
      end

      it 'calculates MFI value' do
        expect(result[:value]).to be_a(Float)
      end

      it 'is in bullish range' do
        expect(result[:state]).to be_in(%i[bullish overbought])
        expect(result[:value]).to be >= 50
      end
    end

    context 'with bearish price & volume increasing' do
      subject(:result) { described_class.call(candles) }

      let(:candles) do
        (1..20).map do |i|
          base = 22_100 - (i * 3)
          { high: base + 2, low: base - 4, close: base - 2, volume: 1000 + (i * 50) }
        end
      end

      it 'is in bearish range' do
        expect(result[:state]).to be_in(%i[bearish oversold])
        expect(result[:value]).to be < 50
      end
    end

    context 'with insufficient data' do
      let(:candles) do
        [{ high: 100, low: 95, close: 98, volume: 100 }]
      end

      it 'returns nil' do
        expect(described_class.call(candles)).to be_nil
      end
    end

    context 'with overbought condition' do
      subject(:result) { described_class.call(candles) }

      let(:candles) do
        (1..20).map do |i|
          base = 22_000 + (i * 25)
          vol = 2000 + (i * 500)
          { high: base + 15, low: base - 3, close: base + 12, volume: vol }
        end
      end

      it 'detects overbought' do
        expect(result[:state]).to eq(:overbought)
        expect(result[:value]).to be > 80
      end
    end

    context 'with oversold condition' do
      subject(:result) { described_class.call(candles) }

      let(:candles) do
        (1..20).map do |i|
          base = 22_200 - (i * 25)
          vol = 2000 + (i * 500)
          { high: base + 3, low: base - 15, close: base - 12, volume: vol }
        end
      end

      it 'detects oversold' do
        expect(result[:state]).to eq(:oversold)
        expect(result[:value]).to be < 20
      end
    end

    context 'when volume is zero (e.g. index/spot candles, which never carry volume)' do
      subject(:result) { described_class.call(candles) }

      let(:candles) do
        (1..20).map do |i|
          base = 22_000 + (i * 10)
          { high: base + 5, low: base - 5, close: base, volume: 0 }
        end
      end

      # Zero volume => raw money flow is zero for every candle => negative_mf.zero?
      # branch always fires => value pins at 100.0/:overbought regardless of price action.
      # Documents that MFI carries no real signal on index data; callers must not gate on it.
      it 'pins at the max value, not a real MFI reading' do
        expect(result[:value]).to eq(100.0)
        expect(result[:state]).to eq(:overbought)
      end
    end

    context 'when all money flow is positive' do
      subject(:result) { described_class.call(candles) }

      let(:candles) do
        (1..20).map do |i|
          { high: 100 + i, low: 90 + i, close: 95 + i, volume: 1000 }
        end
      end

      it 'returns max MFI value' do
        expect(result[:value]).to eq(100.0)
      end

      it 'returns overbought state' do
        expect(result[:state]).to eq(:overbought)
      end
    end
  end
end
