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
    # Default activation_profit_pct is 0.25, activation_sl_offset_pct is 0.10

    it 'is true when profit meets activation threshold (OR logic)' do
      expect(described_class.peak_drawdown_active?(profit_pct: 0.30, current_sl_offset_pct: 0.0)).to be true
    end

    it 'is true when SL offset meets threshold (OR logic)' do
      expect(described_class.peak_drawdown_active?(profit_pct: 0.10, current_sl_offset_pct: 0.15)).to be true
    end

    it 'is true when both thresholds are met' do
      expect(described_class.peak_drawdown_active?(profit_pct: 0.30, current_sl_offset_pct: 0.12)).to be true
    end

    it 'is false when neither threshold is met' do
      expect(described_class.peak_drawdown_active?(profit_pct: 0.10, current_sl_offset_pct: 0.05)).to be false
    end

    it 'emergency override: always true when peak >= 2x activation threshold' do
      # 2x of 0.25 = 0.50. Peak of 0.60 should always activate regardless of SL offset
      expect(described_class.peak_drawdown_active?(profit_pct: 0.60, current_sl_offset_pct: -0.15)).to be true
    end

    it 'emergency override does not trigger below 2x threshold' do
      # 0.20 < 0.50 (2x of 0.25), and profit 0.20 < 0.25 threshold, SL offset -0.15 < 0.10 threshold
      expect(described_class.peak_drawdown_active?(profit_pct: 0.20, current_sl_offset_pct: -0.15)).to be false
    end

    it 'handles zero peak profit' do
      expect(described_class.peak_drawdown_active?(profit_pct: 0.0, current_sl_offset_pct: 0.0)).to be false
    end

    it 'handles negative current (neither threshold met)' do
      expect(described_class.peak_drawdown_active?(profit_pct: -0.05, current_sl_offset_pct: -0.10)).to be false
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
