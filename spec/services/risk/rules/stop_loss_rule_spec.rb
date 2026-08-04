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
    Positions::PositionData.new(
      tracker_id: tracker.id,
      entry_price: 100.0,
      quantity: 10,
      current_ltp: 96.0,
      pnl: -40.0,
      pnl_pct: pnl_pct
    )
  end
  let(:pnl_pct) { -0.04 }
  let(:tracker_snapshot) { { pnl_pct: pnl_pct } }
  let(:risk_config) { { sl_pct: 0.02 } }
  let(:context) do
    Risk::Rules::RuleContext.new(
      position: position,
      tracker: tracker,
      risk_config: risk_config,
      tracker_snapshot: tracker_snapshot
    )
  end
  let(:rule) { described_class.new(config: { sl_pct: 0.02 }) }

  describe '#evaluate' do
    context 'when stop loss is hit' do
      before do
        allow(Live::UnifiedExitChecker).to receive(:loss_limit_hit?)
          .with(tracker, tracker_snapshot)
          .and_return(true)
      end

      it 'returns exit result with STOP_LOSS reason' do
        result = rule.evaluate(context)
        expect(result.exit?).to be true
        expect(result.reason).to eq('STOP_LOSS')
        expect(result.metadata[:pnl_pct]).to eq(-4.0)
      end

      it 'triggers exit when PnL exactly equals threshold' do
        position_data.pnl_pct = -0.02
        tracker_snapshot[:pnl_pct] = -0.02
        result = rule.evaluate(context)
        expect(result.exit?).to be true
      end

      it 'triggers exit when PnL is worse than threshold' do
        position_data.pnl_pct = -0.05
        tracker_snapshot[:pnl_pct] = -0.05
        result = rule.evaluate(context)
        expect(result.exit?).to be true
      end
    end

    context 'when stop loss is not hit' do
      before do
        allow(Live::UnifiedExitChecker).to receive(:loss_limit_hit?)
          .with(tracker, tracker_snapshot)
          .and_return(false)
      end

      it 'returns no_action when PnL is above threshold' do
        position_data.pnl_pct = -0.01
        tracker_snapshot[:pnl_pct] = -0.01
        result = rule.evaluate(context)
        expect(result.no_action?).to be true
      end

      it 'returns no_action when PnL is positive' do
        position_data.pnl_pct = 0.01
        tracker_snapshot[:pnl_pct] = 0.01
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

    describe 'priority' do
      it 'has priority 20' do
        expect(described_class::PRIORITY).to eq(20)
      end
    end
  end
end
