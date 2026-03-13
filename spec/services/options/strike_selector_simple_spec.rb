# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Options::StrikeSelector do
  describe '.strike_type_for_momentum' do
    it 'returns :atm for strong momentum (score 3/3)' do
      expect(described_class.strike_type_for_momentum(3)).to eq(:atm)
    end

    it 'returns :itm for moderate momentum (score 2/3)' do
      expect(described_class.strike_type_for_momentum(2)).to eq(:itm)
    end

    it 'returns :skip for weak momentum (score 1/3)' do
      expect(described_class.strike_type_for_momentum(1)).to eq(:skip)
    end

    it 'returns :skip for no momentum (score 0/3)' do
      expect(described_class.strike_type_for_momentum(0)).to eq(:skip)
    end
  end

  describe '#strike_type' do
    it 'returns :atm for momentum > 0.7' do
      selector = described_class.new(momentum: 0.8)
      expect(selector.strike_type).to eq(:atm)
    end

    it 'returns :itm for momentum > 0.4' do
      selector = described_class.new(momentum: 0.5)
      expect(selector.strike_type).to eq(:itm)
    end

    it 'returns :skip for momentum <= 0.4' do
      selector = described_class.new(momentum: 0.3)
      expect(selector.strike_type).to eq(:skip)
    end
  end
end
