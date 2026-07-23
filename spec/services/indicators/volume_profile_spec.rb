# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Indicators::VolumeProfile do
  describe '#call' do
    context 'with standard range of candles' do
      subject(:result) { described_class.call(candles, bin_size: 10.0) }

      let(:candles) do
        [
          { high: 22_100, low: 22_000, volume: 1000 },
          { high: 22_150, low: 22_050, volume: 2000 },
          { high: 22_200, low: 22_100, volume: 3000 },
          { high: 22_250, low: 22_150, volume: 1500 },
          { high: 22_300, low: 22_200, volume: 2500 }
        ]
      end

      it 'identifies a Point of Control' do
        expect(result[:poc]).not_to be_nil
      end

      it 'returns High Volume Nodes' do
        expect(result[:hvns]).to be_an(Array)
        expect(result[:hvns]).not_to be_empty
      end

      it 'returns Low Volume Nodes' do
        expect(result[:lvns]).to be_an(Array)
      end

      it 'returns total volume' do
        expect(result[:total_volume]).to be_positive
      end

      it 'returns max volume' do
        expect(result[:max_volume]).to be_positive
      end
    end

    context 'with empty candles' do
      subject(:result) { described_class.call(candles) }

      let(:candles) { [] }

      it 'returns empty result' do
        expect(result[:poc]).to be_nil
        expect(result[:hvns]).to be_empty
        expect(result[:lvns]).to be_empty
      end
    end

    context 'with single candle' do
      subject(:result) { described_class.call(candles, bin_size: 10.0) }

      let(:candles) do
        [{ high: 22_100, low: 22_000, volume: 5000 }]
      end

      it 'returns POC within the range' do
        expect(result[:poc]).to be_between(22_000, 22_100)
      end
    end

    context 'with zero volume candles' do
      subject(:result) { described_class.call(candles) }

      let(:candles) do
        [
          { high: 22_100, low: 22_000, volume: 0 },
          { high: 22_150, low: 22_050, volume: 0 }
        ]
      end

      it 'returns empty result when all volume is zero' do
        expect(result[:poc]).to be_nil
        expect(result[:hvns]).to be_empty
      end
    end

    context 'with very tight range (high ≈ low)' do
      subject(:result) { described_class.call(candles, bin_size: 1.0) }

      let(:candles) do
        [
          { high: 22_100, low: 22_099, volume: 1000 },
          { high: 22_101, low: 22_100, volume: 2000 },
          { high: 22_099, low: 22_098, volume: 1500 }
        ]
      end

      it 'identifies a POC' do
        expect(result[:poc]).not_to be_nil
      end

      it 'assigns volume correctly' do
        expect(result[:total_volume]).to eq(4500.0)
      end
    end
  end
end
