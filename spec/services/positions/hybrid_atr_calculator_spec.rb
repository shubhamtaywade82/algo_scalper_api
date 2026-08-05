# frozen_string_literal: true

require 'rails_helper'
require_relative '../../../app/services/positions/hybrid_atr_calculator'

RSpec.describe Positions::HybridATRCalculator do
  describe '.acceleration_factor' do
    it 'returns 1.00 for profit < 15%' do
      expect(described_class.acceleration_factor(0.10)).to eq(1.00)
    end

    it 'returns 0.85 for profit between 15% and 30%' do
      expect(described_class.acceleration_factor(0.20)).to eq(0.85)
    end

    it 'returns 0.70 for profit between 30% and 50%' do
      expect(described_class.acceleration_factor(0.40)).to eq(0.70)
    end

    it 'returns 0.50 for profit >= 50%' do
      expect(described_class.acceleration_factor(0.60)).to eq(0.50)
    end
  end

  describe '.calculate_sl_price' do
    let(:entry_price) { 100.0 }
    let(:current_price) { 120.0 }
    let(:peak_price) { 125.0 }
    let(:atr_value) { 5.0 }

    it 'returns nil if current profit is below activation profit threshold' do
      sl = described_class.calculate_sl_price(
        current_price: 110.0,
        entry_price: 100.0,
        peak_price: 110.0,
        current_profit_pct: 0.10,
        atr_value: atr_value,
        options: { activation_profit_pct: 0.15 }
      )
      expect(sl).to be_nil
    end

    it 'calculates chandelier SL with default multiplier when profit is 20%' do
      # profit 20% -> accel_factor 0.85 -> effective_multiplier = 2.0 * 0.85 = 1.7
      # chandelier_sl = peak (125) - (5.0 * 1.7) = 125 - 8.5 = 116.5
      sl = described_class.calculate_sl_price(
        current_price: current_price,
        entry_price: entry_price,
        peak_price: peak_price,
        current_profit_pct: 0.20,
        atr_value: atr_value,
        options: { base_multiplier: 2.0, activation_profit_pct: 0.15, min_sl_offset_pct: -0.15 }
      )
      expect(sl).to eq(116.5)
    end

    it 'accelerates trailing stop when profit is 55%' do
      # profit 55% -> accel_factor 0.50 -> effective_multiplier = 2.0 * 0.50 = 1.0
      # chandelier_sl = peak (155) - (5.0 * 1.0) = 155 - 5 = 150.0
      sl = described_class.calculate_sl_price(
        current_price: 155.0,
        entry_price: entry_price,
        peak_price: 155.0,
        current_profit_pct: 0.55,
        atr_value: atr_value,
        options: { base_multiplier: 2.0, activation_profit_pct: 0.15 }
      )
      expect(sl).to eq(150.0)
    end

    it 'respects floor SL when chandelier SL is lower than min_sl_offset' do
      # entry 100, min_sl_offset_pct = -0.05 -> floor_sl = 95.0
      # peak 116, atr 20 -> chandelier_sl = 116 - (20 * 1.7) = 82.0
      sl = described_class.calculate_sl_price(
        current_price: 116.0,
        entry_price: entry_price,
        peak_price: 116.0,
        current_profit_pct: 0.16,
        atr_value: 20.0,
        options: { base_multiplier: 2.0, activation_profit_pct: 0.15, min_sl_offset_pct: -0.05 }
      )
      expect(sl).to eq(95.0)
    end

    it 'caps stop loss at current_price' do
      # chandelier SL calculation yields 130, but current_price is 125 -> capped at 125
      sl = described_class.calculate_sl_price(
        current_price: 125.0,
        entry_price: 100.0,
        peak_price: 135.0,
        current_profit_pct: 0.25,
        atr_value: 1.0,
        options: { base_multiplier: 1.0, activation_profit_pct: 0.15 }
      )
      expect(sl).to be <= 125.0
    end
  end
end
