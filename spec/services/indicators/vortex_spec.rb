# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Indicators::Vortex do
  describe '#call' do
    context 'with clear bullish trend candles' do
      subject(:result) { described_class.call(candles) }

      let(:candles) do
        (1..20).map do |i|
          base = 22_000 + (i * 20)
          { high: base + 10, low: base - 5, close: base + 5, volume: 1000 }
        end
      end

      it 'calculates VI+' do
        expect(result[:vi_plus]).to be_a(Float).and(be_positive)
      end

      it 'calculates VI-' do
        expect(result[:vi_minus]).to be_a(Float).and(be_positive)
      end

      it 'detects bullish state' do
        expect(result[:vi_plus]).to be > result[:vi_minus]
        expect(result[:state]).to eq(:bullish)
      end
    end

    context 'with clear bearish trend candles' do
      subject(:result) { described_class.call(candles) }

      let(:candles) do
        (1..20).map do |i|
          base = 22_200 - (i * 20)
          { high: base + 5, low: base - 10, close: base - 5, volume: 1000 }
        end
      end

      it 'detects bearish state' do
        expect(result[:vi_minus]).to be > result[:vi_plus]
        expect(result[:state]).to eq(:bearish)
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

    context 'with sideways/no-trend data' do
      subject(:result) { described_class.call(candles) }

      let(:candles) do
        (1..20).map do |_i|
          { high: rand(22_050..22_054), low: rand(22_041..22_045), close: 22_048, volume: 1000 }
        end
      end

      it 'returns a state' do
        expect(result[:state]).to be_in(%i[bullish bearish neutral])
      end
    end
  end

  describe '.crossover?' do
    context 'when VI+ crosses above VI-' do
      let(:prev_candles) do
        (1..15).map do |i|
          base = 22_000 - (i * 5)
          { high: base + 8, low: base - 8, close: base, volume: 1000 }
        end
      end

      let(:current_candles) do
        (1..16).map do |i|
          base = 22_000 + (i * 15)
          { high: base + 10, low: base - 5, close: base + 5, volume: 1000 }
        end
      end

      it 'detects bullish crossover' do
        expect(described_class.crossover?(prev_candles, current_candles)).to eq(:bullish_crossover)
      end
    end

    context 'when no crossover occurs' do
      let(:prev_candles) do
        (1..16).map do |i|
          base = 22_000 + (i * 10)
          { high: base + 5, low: base - 5, close: base, volume: 1000 }
        end
      end

      let(:current_candles) do
        (1..17).map do |i|
          base = 22_000 + (i * 10)
          { high: base + 5, low: base - 5, close: base, volume: 1000 }
        end
      end

      it 'returns :none' do
        expect(described_class.crossover?(prev_candles, current_candles)).to eq(:none)
      end
    end

    context 'with insufficient data' do
      let(:candles) { [{ high: 100, low: 95, close: 98, volume: 100 }] }

      it 'returns false' do
        expect(described_class.crossover?(candles, candles)).to be false
      end
    end
  end
end
