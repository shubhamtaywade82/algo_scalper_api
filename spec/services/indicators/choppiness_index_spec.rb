# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Indicators::ChoppinessIndex do
  describe '#call' do
    context 'with trending market data' do
      subject(:result) { described_class.call(candles) }

      let(:candles) do
        base = 22_000
        (1..20).map do |i|
          { high: base + (i * 10) + 5, low: base + (i * 10) - 5, close: base + (i * 10), volume: 1000 }
        end
      end

      it 'calculates chop value' do
        expect(result[:value]).to be_a(Float)
      end

      it 'detects trending regime for strong trend' do
        expect(result[:regime]).to eq(:trending)
        expect(result[:value]).to be < 38.0
      end
    end

    context 'with choppy/range-bound data' do
      subject(:result) { described_class.call(candles) }

      let(:candles) do
        (1..20).map do |_i|
          high = rand(22_050..22_059)
          low = rand(21_991..22_000)
          { high: high, low: low, close: low + ((high - low) * rand), volume: 1000 }
        end
      end

      it 'detects choppy regime' do
        expect(result[:regime]).to eq(:choppy)
        expect(result[:value]).to be > 61.0
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

    context 'when range is zero' do
      subject(:result) { described_class.call(candles) }

      let(:candles) do
        (1..20).map { |_i| { high: 100, low: 100, close: 100, volume: 100 } }
      end

      it 'returns max chop value' do
        expect(result[:value]).to eq(100.0)
      end

      it 'returns choppy regime' do
        expect(result[:regime]).to eq(:choppy)
      end
    end
  end
end
