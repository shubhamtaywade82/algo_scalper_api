# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Risk::Rules::TakeProfitRule do
  let(:tracker) do
    instance_double(
      PositionTracker,
      active?: true,
      id: 42,
      entry_price: BigDecimal('100'),
      quantity: 10
    )
  end
  let(:position_data) do
    Positions::PositionData.new(
      tracker_id: tracker.id,
      entry_price: 100.0,
      quantity: 10,
      current_ltp: 107.0,
      pnl: 70.0,
      pnl_pct: 0.07
    )
  end
  let(:risk_config) { { tp_pct: 0.05 } }
  let(:context) do
    Risk::Rules::RuleContext.new(
      position: position,
      tracker: tracker,
      tracker_snapshot: { pnl_pct: pnl_pct },
      risk_config: risk_config
    )
  end
  let(:rule) { described_class.new(config: risk_config) }

  describe '#evaluate' do
    context 'when take profit is hit' do
      it 'returns exit result when PnL exceeds threshold' do
        result = rule.evaluate(context)
        expect(result.exit?).to be true
        expect(result.reason).to include('TP HIT')
        expect(result.reason).to include('7.0%')
        expect(result.metadata[:pnl_pct]).to eq(0.07)
        expect(result.metadata[:tp_pct]).to eq(0.05)
      end

      it 'triggers exit when PnL exactly equals threshold' do
        position_data.pnl_pct = 0.05
        result = rule.evaluate(context)
        expect(result.exit?).to be true
      end

      it 'triggers exit when PnL exceeds threshold' do
        position_data.pnl_pct = 0.10
        result = rule.evaluate(context)
        expect(result.exit?).to be true
      end
    end

    context 'when take profit is not hit' do
      it 'returns no_action when PnL is below threshold' do
        position_data.pnl_pct = 0.03
        result = rule.evaluate(context)
        expect(result.no_action?).to be true
      end

      it 'returns no_action when PnL is negative' do
        position_data.pnl_pct = -0.02
        result = rule.evaluate(context)
        expect(result.no_action?).to be true
      end
    end

  describe '#evaluate' do
    it 'exits when pnl reaches take-profit threshold' do
      result = rule.evaluate(context)

      expect(result).to be_exit
      expect(result.reason).to eq('TAKE_PROFIT')
      expect(result.metadata[:pnl_pct]).to eq(7.0)
    end

    it 'does not exit when pnl is below threshold' do
      allow(context).to receive(:tracker_snapshot).and_return({ pnl_pct: 0.03 })

      expect(rule.evaluate(context)).to be_no_action
    end

    context 'with different thresholds' do
      it 'works with 3% threshold' do
        risk_config[:tp_pct] = 0.03
        position_data.pnl_pct = 0.05
        result = rule.evaluate(context)
        expect(result.exit?).to be true
      end

      it 'works with 10% threshold' do
        risk_config[:tp_pct] = 0.10
        position_data.pnl_pct = 0.07
        result = rule.evaluate(context)
        expect(result.no_action?).to be true
      end
    end

      expect(rule.evaluate(missing_context)).to be_skip
    end
  end
end
