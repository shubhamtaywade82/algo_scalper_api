# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Capital::Allocator do
  let(:entry_price) { 120.0 }
  let(:derivative_lot_size) { 50 }
  let(:capital) { BigDecimal(100_000) }

  before do
    allow(described_class).to receive(:available_cash).and_return(capital)
    allow(Time).to receive(:current).and_return(Time.zone.parse('2026-04-06 10:00 IST'))
  end

  context 'when rupee-based sizing is enabled' do
    it 'caps quantity using per-index capital_alloc_pct' do
      cfg_30 = { key: 'NIFTY', capital_alloc_pct: 0.30 }
      cfg_50 = { key: 'NIFTY', capital_alloc_pct: 0.50 }

      qty_30 = described_class.qty_for(
        index_cfg: cfg_30,
        entry_price: entry_price,
        derivative_lot_size: derivative_lot_size,
        scale_multiplier: 1
      )
      qty_50 = described_class.qty_for(
        index_cfg: cfg_50,
        entry_price: entry_price,
        derivative_lot_size: derivative_lot_size,
        scale_multiplier: 1
      )

      expect(qty_30).to eq(250)
      expect(qty_50).to eq(400)
      expect(qty_50).to be > qty_30
    end

    context 'when index omits capital_alloc_pct' do
      it 'uses sizing.allocation_cap_pct when set' do
        base = AlgoConfig.fetch
        allow(AlgoConfig).to receive(:fetch).and_return(
          base.deep_merge(sizing: { allocation_cap_pct: 0.50 })
        )

        qty = described_class.qty_for(
          index_cfg: { key: 'NIFTY' },
          entry_price: entry_price,
          derivative_lot_size: derivative_lot_size,
          scale_multiplier: 1
        )

        expect(qty).to eq(400)
      end
    end
  end
end
