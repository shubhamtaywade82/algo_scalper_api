# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Options::DeltaAccelerationDetector do
  let(:index_prices) { [24200.0, 24215.0] }
  let(:option_prices) { [110.0, 150.0] }
  let(:volumes) { Array.new(20, 1000.0) + [2000.0] }
  let(:oi) { [500_000, 510_000] }

  let(:detector) do
    described_class.new(
      index_prices: index_prices,
      option_prices: option_prices,
      volumes: volumes,
      oi: oi
    )
  end

  describe '#delta_ratio' do
    it 'calculates the ratio of option return to index return' do
      # index_ret = (24215 - 24200) / 24200 = 15 / 24200 = 0.0006198
      # option_ret = (150 - 110) / 110 = 40 / 110 = 0.363636
      # ratio = 0.363636 / 0.0006198 = 586.66
      expect(detector.delta_ratio).to be > 500
    end

    it 'returns 0 if index and option move in opposite directions' do
      opposite_detector = described_class.new(
        index_prices: [24200.0, 24215.0],
        option_prices: [110.0, 100.0],
        volumes: volumes,
        oi: oi
      )
      expect(opposite_detector.delta_ratio).to eq(0.0)
    end
  end

  describe '#signal' do
    it 'returns :strong for high delta ratio and volume expansion' do
      # Ratio > 12, Vol ratio 2.0 > 1.5, OI rising
      expect(detector.signal).to eq(:strong)
    end

    it 'returns :moderate for moderate delta ratio' do
      # Setup for ratio ~10
      # index_ret = 0.01 (1%)
      # option_ret = 0.10 (10%)
      moderate_detector = described_class.new(
        index_prices: [100.0, 101.0],
        option_prices: [100.0, 110.0],
        volumes: volumes,
        oi: oi
      )
      expect(moderate_detector.signal).to eq(:moderate)
    end

    it 'returns :none if volume ratio is low' do
      low_vol_detector = described_class.new(
        index_prices: index_prices,
        option_prices: option_prices,
        volumes: Array.new(21, 1000.0),
        oi: oi
      )
      expect(low_vol_detector.signal).to eq(:none)
    end

    it 'returns :none if OI is not rising' do
      falling_oi_detector = described_class.new(
        index_prices: index_prices,
        option_prices: option_prices,
        volumes: volumes,
        oi: [500_000, 490_000]
      )
      expect(falling_oi_detector.signal).to eq(:none)
    end
  end
end
