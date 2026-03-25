# frozen_string_literal: true
  
require 'rails_helper'

RSpec.describe Capital::Allocator do
  describe '.qty_for' do
    let(:index_cfg) { { key: 'NIFTY', capital_alloc_pct: 0.30 } }
    let(:entry_price) { 120.0 }
    let(:derivative_lot_size) { 50 }

    before do
      allow(described_class).to receive(:available_cash).and_return(BigDecimal(100_000))
      allow(AlgoConfig).to receive(:fetch).and_return(sizing: { post_1100_multiplier: 0.5 })
      allow(Time).to receive(:current).and_return(Time.zone.parse('2026-03-24 10:45:00 IST'))
    end

    context 'when current time is before 11:00 IST' do
      it 'does not apply post-11 multiplier' do
        qty = described_class.qty_for(
          index_cfg: index_cfg,
          entry_price: entry_price,
          derivative_lot_size: derivative_lot_size,
          scale_multiplier: 2
        )

        expect(qty).to be >= derivative_lot_size
      end
    end

    context 'when current time is after 11:00 IST' do
      before do
        allow(Time).to receive(:current).and_return(Time.zone.parse('2026-03-24 11:30:00 IST'))
      end

      it 'reduces effective multiplier for sizing' do
        before_qty = described_class.qty_for(
          index_cfg: index_cfg,
          entry_price: entry_price,
          derivative_lot_size: derivative_lot_size,
          scale_multiplier: 2
        )

        allow(Time).to receive(:current).and_return(Time.zone.parse('2026-03-24 10:30:00 IST'))
        after_qty = described_class.qty_for(
          index_cfg: index_cfg,
          entry_price: entry_price,
          derivative_lot_size: derivative_lot_size,
          scale_multiplier: 2
        )

        expect(before_qty).to be < after_qty
      end
    end
  end
end
