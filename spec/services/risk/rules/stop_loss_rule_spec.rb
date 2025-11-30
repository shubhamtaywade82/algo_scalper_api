# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Risk::Rules::StopLossRule do
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
      current_ltp: 96.0,
      pnl: -40.0,
      pnl_pct: -4.0
    )
  end
  let(:risk_config) { { sl_pct: 2.0 } }
  let(:context) do
    Risk::Rules::RuleContext.new(
      position: position_data,
      tracker: tracker,
      risk_config: risk_config
    )
  end
  let(:rule) { described_class.new(config: risk_config) }

  describe '#evaluate' do
    context 'when stop loss is hit' do
      it 'returns exit result when PnL drops below threshold' do
        result = rule.evaluate(context)
        expect(result.exit?).to be true
        expect(result.reason).to include('SL HIT')
        expect(result.reason).to include('-4.00%')
        expect(result.metadata[:pnl_pct]).to eq(-4.0)
        expect(result.metadata[:sl_pct]).to eq(2.0)
      end

      it 'triggers exit when PnL exactly equals threshold' do
        position_data.pnl_pct = -2.0
        result = rule.evaluate(context)
        expect(result.exit?).to be true
      end

      it 'triggers exit when PnL is worse than threshold' do
        position_data.pnl_pct = -5.0
        result = rule.evaluate(context)
        expect(result.exit?).to be true
      end
    end

    context 'when stop loss is not hit' do
      it 'returns no_action when PnL is above threshold' do
        position_data.pnl_pct = -1.0
        result = rule.evaluate(context)
        expect(result.no_action?).to be true
      end

      it 'returns no_action when PnL is positive' do
        position_data.pnl_pct = 1.0
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

    context 'when stop loss threshold is zero' do
      it 'returns skip_result when sl_pct is 0' do
        risk_config[:sl_pct] = 0
        result = rule.evaluate(context)
        expect(result.skip?).to be true
      end
    end

    context 'when stop loss threshold is not configured' do
      it 'returns skip_result when sl_pct is nil' do
        risk_config.delete(:sl_pct)
        result = rule.evaluate(context)
        expect(result.skip?).to be true
      end
    end

    context 'with different thresholds' do
      it 'works with 1% threshold' do
        risk_config[:sl_pct] = 1.0
        position_data.pnl_pct = -1.5
        result = rule.evaluate(context)
        expect(result.exit?).to be true
      end

      it 'works with 5% threshold' do
        risk_config[:sl_pct] = 5.0
        position_data.pnl_pct = -3.0
        result = rule.evaluate(context)
        expect(result.no_action?).to be true
      end
    end

    describe 'priority' do
      it 'has priority 20' do
        expect(described_class::PRIORITY).to eq(20)
      end
    end
  end
end
