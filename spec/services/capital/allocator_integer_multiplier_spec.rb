# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Capital::Allocator do
  let(:index_cfg) do
    {
      key: 'NIFTY',
      capital_alloc_pct: 0.30
    }
  end
  let(:entry_price) { 120.0 }
  let(:derivative_lot_size) { 50 }

  before do
    allow(described_class).to receive(:available_cash).and_return(BigDecimal(100_000))
  end

  describe 'integer multiplier enforcement' do
    it 'normalizes non-integer multiplier to integer' do
      qty = described_class.qty_for(
        index_cfg: index_cfg,
        entry_price: entry_price,
        derivative_lot_size: derivative_lot_size,
        scale_multiplier: 1.5
      )

      expect(qty).to be > 0
      expect(qty % derivative_lot_size).to eq(0)
    end

    it 'enforces minimum multiplier of 1' do
      qty = described_class.qty_for(
        index_cfg: index_cfg,
        entry_price: entry_price,
        derivative_lot_size: derivative_lot_size,
        scale_multiplier: 0
      )

      expect(qty).to be > 0
    end

    it 'uses derivative lot_size for quantity calculation' do
      qty = described_class.qty_for(
        index_cfg: index_cfg,
        entry_price: entry_price,
        derivative_lot_size: derivative_lot_size,
        scale_multiplier: 1
      )

      expect(qty % derivative_lot_size).to eq(0)
    end

    it 'returns 0 when insufficient capital' do
      allow(described_class).to receive(:available_cash).and_return(BigDecimal(100))

      qty = described_class.qty_for(
        index_cfg: index_cfg,
        entry_price: entry_price,
        derivative_lot_size: derivative_lot_size,
        scale_multiplier: 1
      )

      expect(qty).to eq(0)
    end
  end

  describe 'quantity calculation' do
    it 'calculates quantity as multiple of lot_size' do
      qty = described_class.qty_for(
        index_cfg: index_cfg,
        entry_price: entry_price,
        derivative_lot_size: derivative_lot_size,
        scale_multiplier: 1
      )

      expect(qty).to be >= derivative_lot_size
      expect(qty % derivative_lot_size).to eq(0)
    end

    it 'applies multiplier correctly' do
      qty1 = described_class.qty_for(
        index_cfg: index_cfg,
        entry_price: entry_price,
        derivative_lot_size: derivative_lot_size,
        scale_multiplier: 1
      )

      qty2 = described_class.qty_for(
        index_cfg: index_cfg,
        entry_price: entry_price,
        derivative_lot_size: derivative_lot_size,
        scale_multiplier: 2
      )

      expect(qty2).to be >= qty1
    end
  end
end
