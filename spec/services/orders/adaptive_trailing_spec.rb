# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Orders::AdaptiveTrailing do
  describe '#stop' do
    context 'with low regime' do
      it 'calculates stop based on 15% trail' do
        trailing = described_class.new(highest: 100, regime: :low)
        expect(trailing.stop).to eq(85.0)
      end
    end

    context 'with normal regime' do
      it 'calculates stop based on 25% trail' do
        trailing = described_class.new(highest: 100, regime: :normal)
        expect(trailing.stop).to eq(75.0)
      end

      it 'defaults to normal if regime is unknown' do
        trailing = described_class.new(highest: 100, regime: :unknown)
        expect(trailing.stop).to eq(75.0)
      end
    end

    context 'with high regime' do
      it 'calculates stop based on 35% trail' do
        trailing = described_class.new(highest: 100, regime: :high)
        expect(trailing.stop).to eq(65.0)
      end
    end

    it 'handles string highest value' do
      trailing = described_class.new(highest: '200.5', regime: :normal)
      # 200.5 * 0.75 = 150.375 -> rounded to 150.38
      expect(trailing.stop).to eq(150.38)
    end
  end
end
