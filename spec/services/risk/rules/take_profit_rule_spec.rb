# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Risk::Rules::TakeProfitRule do
  let(:instrument) { create(:instrument, :nifty_future) }
  let(:tracker) do
    create(
      :position_tracker,
      instrument: instrument,
      status: 'active',
      entry_price: 100.0,
      quantity: 10
    )
  end
  let(:position_data) do
    Positions::ActiveCache::PositionData.new(
      tracker_id: tracker.id,
      entry_price: 100.0,
      quantity: 10,
      current_ltp: 107.0,
      pnl: 70.0,
      pnl_pct: 7.0
    )
  end
  let(:risk_config) { { tp_pct: 5.0 } }
  let(:context) do
    Risk::Rules::RuleContext.new(
      position: position_data,
      tracker: tracker,
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
        expect(result.reason).to include('7.00%')
        expect(result.metadata[:pnl_pct]).to eq(7.0)
        expect(result.metadata[:tp_pct]).to eq(5.0)
      end

      it 'triggers exit when PnL exactly equals threshold' do
        position_data.pnl_pct = 5.0
        result = rule.evaluate(context)
        expect(result.exit?).to be true
      end

      it 'triggers exit when PnL exceeds threshold' do
        position_data.pnl_pct = 10.0
        result = rule.evaluate(context)
        expect(result.exit?).to be true
      end
    end

    context 'when take profit is not hit' do
      it 'returns no_action when PnL is below threshold' do
        position_data.pnl_pct = 3.0
        result = rule.evaluate(context)
        expect(result.no_action?).to be true
      end

      it 'returns no_action when PnL is negative' do
        position_data.pnl_pct = -2.0
        result = rule.evaluate(context)
        expect(result.no_action?).to be true
      end
    end

    context 'when position is exited' do
      it 'returns skip_result' do
        tracker.update(status: 'exited')
        result = rule.evaluate(context)
        expect(result.skip?).to be true
      end
    end

    context 'when PnL data is missing' do
      it 'returns skip_result when pnl_pct is nil' do
        position_data.pnl_pct = nil
        result = rule.evaluate(context)
        expect(result.skip?).to be true
      end
    end

    context 'when take profit threshold is zero' do
      it 'returns skip_result when tp_pct is 0' do
        risk_config[:tp_pct] = 0
        result = rule.evaluate(context)
        expect(result.skip?).to be true
      end
    end

    context 'when take profit threshold is not configured' do
      it 'returns skip_result when tp_pct is nil' do
        risk_config.delete(:tp_pct)
        result = rule.evaluate(context)
        expect(result.skip?).to be true
      end
    end

    context 'with different thresholds' do
      it 'works with 3% threshold' do
        risk_config[:tp_pct] = 3.0
        position_data.pnl_pct = 5.0
        result = rule.evaluate(context)
        expect(result.exit?).to be true
      end

      it 'works with 10% threshold' do
        risk_config[:tp_pct] = 10.0
        position_data.pnl_pct = 7.0
        result = rule.evaluate(context)
        expect(result.no_action?).to be true
      end
    end

    describe 'priority' do
      it 'has priority 30' do
        expect(described_class::PRIORITY).to eq(30)
      end
    end
  end
end
