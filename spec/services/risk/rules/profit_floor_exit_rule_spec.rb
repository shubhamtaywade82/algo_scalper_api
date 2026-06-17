# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Risk::Rules::ProfitFloorExitRule do
  subject(:rule) { described_class.new(config: {}) }

  let(:tracker) do
    instance_double(
      PositionTracker,
      order_no: 'ORD001',
      entry_price: 99.0,
      quantity: 250,
      high_water_mark_pnl: 1_131.0
    )
  end
  let(:snapshot) do
    {
      ltp: 102.0,
      pnl: 500.0,
      pnl_pct: 0.02,
      hwm_pnl: 1_131.0
    }
  end
  let(:context) do
    instance_double(
      Risk::Rules::RuleContext,
      active?: true,
      pnl_pct: snapshot[:pnl_pct],
      pnl_rupees: snapshot[:pnl],
      high_water_mark: snapshot[:hwm_pnl],
      entry_price: 99.0,
      quantity: 250,
      tracker: tracker,
      tracker_snapshot: snapshot
    )
  end

  before do
    allow(AlgoConfig).to receive(:fetch).and_return(
      risk: {
        profit_floor: {
          enabled: true,
          lock_pct: 0.025,
          min_arm_rupees: 350,
          trail_pct: 0.72
        }
      }
    )
  end

  describe '#evaluate' do
    context 'when give-back breaches trailing floor' do
      it 'exits on tick path' do
        result = rule.evaluate(context)

        expect(result.exit?).to be true
        expect(result.reason).to include('PROFIT_FLOOR_TICK')
        expect(result.metadata[:floor_rupees]).to eq((1_131.0 * 0.72).ceil)
      end
    end

    context 'when PnL is above floor' do
      it 'returns no_action' do
        allow(context).to receive(:pnl_rupees).and_return(900.0)
        result = rule.evaluate(context)

        expect(result.no_action?).to be true
      end
    end
  end
end
