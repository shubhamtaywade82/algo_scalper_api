# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Positions::TrailingConfig do
  describe '.sl_offset_for' do
    it 'returns nil below the first tier threshold' do
      expect(described_class.sl_offset_for(0)).to be_nil
      expect(described_class.sl_offset_for(3.5)).to be_nil
    end

    it 'returns the matching tier offset for qualifying profit' do
      expect(described_class.sl_offset_for(5.0)).to eq(-15.0)
      expect(described_class.sl_offset_for(10.0)).to eq(-5.0)
      expect(described_class.sl_offset_for(25.0)).to eq(10.0)
      expect(described_class.sl_offset_for(150.0)).to eq(60.0)
    end
  end

  describe '.peak_drawdown_active?' do
    it 'is false when profit has not reached activation threshold' do
      expect(described_class.peak_drawdown_active?(profit_pct: 20.0, current_sl_offset_pct: 15.0)).to be false
    end

    it 'is false when SL offset is below minimum requirement' do
      expect(described_class.peak_drawdown_active?(profit_pct: 30.0, current_sl_offset_pct: 5.0)).to be false
    end

    it 'is true only when both thresholds are met' do
      expect(described_class.peak_drawdown_active?(profit_pct: 30.0, current_sl_offset_pct: 12.0)).to be true
    end
  end

  describe '.sl_price_from_entry' do
    it 'raises when entry price is missing' do
      expect { described_class.sl_price_from_entry(nil, -15) }.to raise_error(ArgumentError)
    end

    it 'converts offset to absolute price' do
      expect(described_class.sl_price_from_entry(100.0, -15.0)).to eq(85.0)
      expect(described_class.sl_price_from_entry(100.0, 10.0)).to eq(110.0)
    end
  end
end
