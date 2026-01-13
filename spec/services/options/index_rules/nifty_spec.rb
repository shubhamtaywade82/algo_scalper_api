# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Options::IndexRules::Nifty do
  let(:rules) { described_class.new }

  describe '#lot_size' do
    it 'returns 75' do
      expect(rules.lot_size).to eq(75)
    end
  end

  describe '#atm' do
    it 'rounds to nearest 50' do
      expect(rules.atm(25_123)).to eq(25_100)
      expect(rules.atm(25_150)).to eq(25_150)
      expect(rules.atm(25_175)).to eq(25_200)
    end
  end

  describe '#valid_liquidity?' do
    it 'returns true for volume >= 30000' do
      candidate = { volume: 50_000 }
      expect(rules.valid_liquidity?(candidate)).to be true
    end

    it 'returns false for volume < 30000' do
      candidate = { volume: 20_000 }
      expect(rules.valid_liquidity?(candidate)).to be false
    end
  end

  describe '#valid_spread?' do
    it 'returns true for spread <= 0.3%' do
      candidate = { bid: 150.0, ask: 150.45 } # 0.3% spread
      expect(rules.valid_spread?(candidate)).to be true
    end

    it 'returns false for spread > 0.3%' do
      candidate = { bid: 150.0, ask: 151.0 } # 0.67% spread
      expect(rules.valid_spread?(candidate)).to be false
    end
  end

  describe '#valid_premium?' do
    it 'returns true for premium >= 25' do
      candidate = { ltp: 30.0 }
      expect(rules.valid_premium?(candidate)).to be true
    end

    it 'returns false for premium < 25' do
      candidate = { ltp: 20.0 }
      expect(rules.valid_premium?(candidate)).to be false
    end
  end
end
