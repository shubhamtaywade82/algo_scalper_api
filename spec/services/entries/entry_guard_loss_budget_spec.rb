# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Entries::EntryGuard do
  describe '.cap_quantity_by_loss_budget' do
    let(:index_cfg) { { key: 'NIFTY' } }
    let(:daily_limits) { instance_double(Live::DailyLimits) }

    # ltp 33.45 with a 20% premium stop: ₹6.69 per unit, ₹434.85 per 65-unit lot; fees ₹40 a round trip.
    before do
      allow(Live::DailyLimits).to receive(:new).and_return(daily_limits)
      allow(Entries::MetaBuilder).to receive(:supertrend_sl_decimal).and_return(0.2)
      allow(BrokerFeeCalculator).to receive(:fee_per_trade).and_return(BigDecimal('40'))
    end

    def cap(quantity)
      described_class.send(:cap_quantity_by_loss_budget, quantity, index_cfg: index_cfg, ltp: 33.45, lot_size: 65)
    end

    it 'cuts the quantity so a stop-out fits the remaining budget' do
      allow(daily_limits).to receive(:remaining_loss_budget).and_return(1_000.0)

      expect(cap(520)).to eq(130)
    end

    it 'leaves the quantity alone when the budget covers it' do
      allow(daily_limits).to receive(:remaining_loss_budget).and_return(50_000.0)

      expect(cap(520)).to eq(520)
    end

    it 'allows nothing once the budget is spent' do
      allow(daily_limits).to receive(:remaining_loss_budget).and_return(0.0)

      expect(cap(520)).to eq(0)
    end

    it 'leaves the quantity alone when no loss limit is configured' do
      allow(daily_limits).to receive(:remaining_loss_budget).and_return(nil)

      expect(cap(520)).to eq(520)
    end

    it 'fails closed when the budget cannot be read' do
      allow(daily_limits).to receive(:remaining_loss_budget).and_raise(Redis::CannotConnectError)
      allow(Rails.logger).to receive(:error)

      expect(cap(520)).to eq(0)
    end
  end
end
