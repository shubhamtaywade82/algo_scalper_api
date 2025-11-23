# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Positions::TrailingConfig do
  describe '.PEAK_DRAWDOWN_PCT' do
    it 'is set to 5.0' do
      expect(described_class::PEAK_DRAWDOWN_PCT).to eq(5.0)
    end
  end

  describe '.TIERS' do
    it 'contains 8 tiers' do
      expect(described_class::TIERS.size).to eq(8)
    end

    it 'has tiers in ascending threshold order' do
      thresholds = described_class::TIERS.map { |t| t[:threshold_pct] }
      expect(thresholds).to eq(thresholds.sort)
    end

    it 'has all required keys for each tier' do
      described_class::TIERS.each do |tier|
        expect(tier).to have_key(:threshold_pct)
        expect(tier).to have_key(:sl_offset_pct)
      end
    end

    it 'has correct tier values' do
      expected_tiers = [
        { threshold_pct: 5.0, sl_offset_pct: -15.0 },
        { threshold_pct: 10.0, sl_offset_pct: -5.0 },
        { threshold_pct: 15.0, sl_offset_pct: 0.0 },
        { threshold_pct: 25.0, sl_offset_pct: 10.0 },
        { threshold_pct: 40.0, sl_offset_pct: 20.0 },
        { threshold_pct: 60.0, sl_offset_pct: 30.0 },
        { threshold_pct: 80.0, sl_offset_pct: 40.0 },
        { threshold_pct: 120.0, sl_offset_pct: 60.0 }
      ]
      expect(described_class::TIERS).to eq(expected_tiers)
    end
  end

  describe '.sl_offset_for' do
    context 'when profit is below first tier' do
      it 'returns first tier offset for profit < 5%' do
        expect(described_class.sl_offset_for(0.0)).to eq(-15.0)
        expect(described_class.sl_offset_for(2.5)).to eq(-15.0)
        expect(described_class.sl_offset_for(4.9)).to eq(-15.0)
      end
    end

    context 'when profit matches tier thresholds exactly' do
      it 'returns correct offset for 5% threshold' do
        expect(described_class.sl_offset_for(5.0)).to eq(-15.0)
      end

      it 'returns correct offset for 10% threshold' do
        expect(described_class.sl_offset_for(10.0)).to eq(-5.0)
      end

      it 'returns correct offset for 15% threshold' do
        expect(described_class.sl_offset_for(15.0)).to eq(0.0)
      end

      it 'returns correct offset for 25% threshold' do
        expect(described_class.sl_offset_for(25.0)).to eq(10.0)
      end

      it 'returns correct offset for 40% threshold' do
        expect(described_class.sl_offset_for(40.0)).to eq(20.0)
      end

      it 'returns correct offset for 60% threshold' do
        expect(described_class.sl_offset_for(60.0)).to eq(30.0)
      end

      it 'returns correct offset for 80% threshold' do
        expect(described_class.sl_offset_for(80.0)).to eq(40.0)
      end

      it 'returns correct offset for 120% threshold' do
        expect(described_class.sl_offset_for(120.0)).to eq(60.0)
      end
    end

    context 'when profit is between tiers' do
      it 'returns lower tier offset for profit between 5% and 10%' do
        expect(described_class.sl_offset_for(7.5)).to eq(-15.0)
      end

      it 'returns correct tier offset for profit between 10% and 15%' do
        expect(described_class.sl_offset_for(12.0)).to eq(-5.0)
      end

      it 'returns correct tier offset for profit between 15% and 25%' do
        expect(described_class.sl_offset_for(20.0)).to eq(0.0)
      end

      it 'returns correct tier offset for profit between 25% and 40%' do
        expect(described_class.sl_offset_for(30.0)).to eq(10.0)
      end

      it 'returns correct tier offset for profit between 40% and 60%' do
        expect(described_class.sl_offset_for(50.0)).to eq(20.0)
      end

      it 'returns correct tier offset for profit between 60% and 80%' do
        expect(described_class.sl_offset_for(70.0)).to eq(30.0)
      end

      it 'returns correct tier offset for profit between 80% and 120%' do
        expect(described_class.sl_offset_for(100.0)).to eq(40.0)
      end
    end

    context 'when profit exceeds highest tier' do
      it 'returns highest tier offset for profit > 120%' do
        expect(described_class.sl_offset_for(150.0)).to eq(60.0)
        expect(described_class.sl_offset_for(200.0)).to eq(60.0)
        expect(described_class.sl_offset_for(500.0)).to eq(60.0)
      end
    end

    context 'edge cases' do
      it 'handles negative profit' do
        expect(described_class.sl_offset_for(-10.0)).to eq(-15.0)
      end

      it 'handles zero profit' do
        expect(described_class.sl_offset_for(0.0)).to eq(-15.0)
      end

      it 'handles very small positive profit' do
        expect(described_class.sl_offset_for(0.1)).to eq(-15.0)
      end
    end
  end

  describe '.peak_drawdown_triggered?' do
    context 'when drawdown is below threshold' do
      it 'returns false for drawdown < 5%' do
        expect(described_class.peak_drawdown_triggered?(10.0, 6.0)).to be false
        expect(described_class.peak_drawdown_triggered?(20.0, 16.0)).to be false
        expect(described_class.peak_drawdown_triggered?(50.0, 46.0)).to be false
      end

      it 'returns false when current >= peak' do
        expect(described_class.peak_drawdown_triggered?(10.0, 10.0)).to be false
        expect(described_class.peak_drawdown_triggered?(10.0, 15.0)).to be false
      end
    end

    context 'when drawdown equals threshold' do
      it 'returns true for drawdown == 5%' do
        expect(described_class.peak_drawdown_triggered?(10.0, 5.0)).to be true
        expect(described_class.peak_drawdown_triggered?(20.0, 15.0)).to be true
      end
    end

    context 'when drawdown exceeds threshold' do
      it 'returns true for drawdown > 5%' do
        expect(described_class.peak_drawdown_triggered?(10.0, 4.0)).to be true
        expect(described_class.peak_drawdown_triggered?(20.0, 10.0)).to be true
        expect(described_class.peak_drawdown_triggered?(50.0, 40.0)).to be true
      end
    end

    context 'edge cases' do
      it 'returns false when peak_profit_pct is nil' do
        expect(described_class.peak_drawdown_triggered?(nil, 10.0)).to be false
      end

      it 'returns false when current_profit_pct is nil' do
        expect(described_class.peak_drawdown_triggered?(10.0, nil)).to be false
      end

      it 'returns false when both are nil' do
        expect(described_class.peak_drawdown_triggered?(nil, nil)).to be false
      end
    end
  end

  describe '.calculate_sl_price' do
    context 'with valid entry price and profit' do
      it 'calculates SL for 0% profit (first tier)' do
        entry = 100.0
        sl = described_class.calculate_sl_price(entry, 0.0)
        # -15% offset: 100 * (1 + (-15/100)) = 100 * 0.85 = 85.0
        expect(sl).to eq(85.0)
      end

      it 'calculates SL for 7.5% profit (first tier)' do
        entry = 100.0
        sl = described_class.calculate_sl_price(entry, 7.5)
        # -15% offset: 100 * 0.85 = 85.0
        expect(sl).to eq(85.0)
      end

      it 'calculates SL for 12% profit (second tier)' do
        entry = 100.0
        sl = described_class.calculate_sl_price(entry, 12.0)
        # -5% offset: 100 * (1 + (-5/100)) = 100 * 0.95 = 95.0
        expect(sl).to eq(95.0)
      end

      it 'calculates SL for 20% profit (third tier - breakeven)' do
        entry = 100.0
        sl = described_class.calculate_sl_price(entry, 20.0)
        # 0% offset: 100 * (1 + 0/100) = 100.0
        expect(sl).to eq(100.0)
      end

      it 'calculates SL for 30% profit (fourth tier)' do
        entry = 100.0
        sl = described_class.calculate_sl_price(entry, 30.0)
        # +10% offset: 100 * (1 + 10/100) = 100 * 1.10 = 110.0
        expect(sl).to eq(110.0)
      end

      it 'calculates SL for 50% profit (fifth tier)' do
        entry = 100.0
        sl = described_class.calculate_sl_price(entry, 50.0)
        # +20% offset: 100 * 1.20 = 120.0
        expect(sl).to eq(120.0)
      end

      it 'calculates SL for 150% profit (highest tier)' do
        entry = 100.0
        sl = described_class.calculate_sl_price(entry, 150.0)
        # +60% offset: 100 * 1.60 = 160.0
        expect(sl).to eq(160.0)
      end
    end

    context 'with invalid entry price' do
      it 'returns nil for nil entry price' do
        expect(described_class.calculate_sl_price(nil, 10.0)).to be_nil
      end

      it 'returns nil for zero entry price' do
        expect(described_class.calculate_sl_price(0.0, 10.0)).to be_nil
      end

      it 'returns nil for negative entry price' do
        expect(described_class.calculate_sl_price(-10.0, 10.0)).to be_nil
      end
    end
  end

  describe '.tiers' do
    it 'returns a copy of TIERS' do
      tiers = described_class.tiers
      expect(tiers).to eq(described_class::TIERS)
      expect(tiers).not_to be(described_class::TIERS) # Different object
    end

    it 'allows modification without affecting original' do
      tiers = described_class.tiers
      tiers << { threshold_pct: 200.0, sl_offset_pct: 100.0 }
      expect(described_class::TIERS.size).to eq(8) # Original unchanged
    end
  end
end

