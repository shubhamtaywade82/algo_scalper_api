# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Positions::TrailingConfig do
  describe '.sl_offset_for' do
    it 'returns nil below the first tier threshold' do
      expect(described_class.sl_offset_for(0)).to be_nil
      expect(described_class.sl_offset_for(0.035)).to be_nil
    end

    it 'returns the matching tier offset for qualifying profit (decimal format)' do
      expect(described_class.sl_offset_for(0.05)).to eq(-0.15)
      expect(described_class.sl_offset_for(0.10)).to eq(-0.05)
      expect(described_class.sl_offset_for(0.25)).to eq(0.10)
      expect(described_class.sl_offset_for(1.50)).to eq(0.60)
    end
  end

  describe '.peak_drawdown_active?' do
    it 'is false when profit has not reached activation threshold' do
      expect(described_class.peak_drawdown_active?(profit_pct: 0.20, current_sl_offset_pct: 0.15)).to be false
    end

    it 'is false when SL offset is below minimum requirement' do
      expect(described_class.peak_drawdown_active?(profit_pct: 0.30, current_sl_offset_pct: 0.05)).to be false
    end

    it 'is true only when both thresholds are met' do
      expect(described_class.peak_drawdown_active?(profit_pct: 0.30, current_sl_offset_pct: 0.12)).to be true
    end
  end

  describe '.sl_price_from_entry' do
    it 'raises when entry price is missing' do
      expect { described_class.sl_price_from_entry(nil, -0.15) }.to raise_error(ArgumentError)
    end

    it 'converts offset to absolute price (decimal format: -0.15 = -15%)' do
      expect(described_class.sl_price_from_entry(100.0, -0.15)).to eq(85.0)
      expect(described_class.sl_price_from_entry(100.0, 0.10)).to eq(110.0)
    end
  end
end
