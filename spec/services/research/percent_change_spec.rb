# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Research::PercentChange do
  describe '.of' do
    it 'computes percentage move of value relative to reference' do
      expect(described_class.of(110, 100)).to eq(10.0)
      expect(described_class.of(90, 100)).to eq(-10.0)
    end

    it 'returns nil when the reference is zero' do
      expect(described_class.of(10, 0)).to be_nil
    end
  end
end
