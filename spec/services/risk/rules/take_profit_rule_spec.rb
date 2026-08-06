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
    Positions::PositionData.new(
      tracker_id: tracker.id,
      entry_price: 100.0,
      quantity: 10,
      current_ltp: 107.0,
      pnl: 70.0,
      pnl_pct: 0.07,
      high_water_mark: 0.0
    )
  end
  let(:tp_pct) { 0.05 }
  let(:risk_config) { { tp_pct: tp_pct } }
  let(:context) do
    Risk::Rules::RuleContext.new(
      position: position_data,
      tracker: tracker,
      risk_config: risk_config,
      tracker_snapshot: { pnl_pct: position_data.pnl_pct, hwm_pnl: position_data.high_water_mark }
    )
  end
  let(:rule) { described_class.new(config: risk_config) }

  before do
    # UnifiedExitChecker.exit_config caches on class-level instance variables
    # with a 30s TTL - reset it so each example's AlgoConfig.fetch stub takes
    # effect instead of a stale config from a previous example.
    Live::UnifiedExitChecker.instance_variable_set(:@exit_config, nil)
    Live::UnifiedExitChecker.instance_variable_set(:@exit_config_expires_at, nil)
    allow(AlgoConfig).to receive(:fetch).and_return(risk: { tp_pct: tp_pct, trailing: { activation_pct: 1.0 } })
  end

  describe '#evaluate' do
    context 'when take profit is hit' do
      it 'returns exit result when PnL exceeds threshold' do
        result = rule.evaluate(context)
        expect(result.exit?).to be true
        expect(result.reason).to eq('TAKE_PROFIT')
        expect(result.metadata[:pnl_pct]).to eq(7.0)
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

    context 'when position is exited' do
      it 'returns skip_result' do
        tracker.update(status: 'exited')
        result = rule.evaluate(context)
        expect(result.skip?).to be true
      end
    end

    context 'when PnL data is missing' do
      it 'returns no_action when pnl_pct is nil' do
        position_data.pnl_pct = nil
        result = rule.evaluate(context)
        expect(result.no_action?).to be true
      end
    end

    context 'when take profit threshold is zero' do
      let(:tp_pct) { 0 }

      it 'exits immediately on any profit when tp_pct is 0 (0% threshold, not disabled)' do
        # exit_config treats 0 as a real configured value (pnl_pct >= 0),
        # not as "disabled" - any non-negative pnl_pct triggers immediately.
        result = rule.evaluate(context)
        expect(result.exit?).to be true
      end
    end

    context 'with different thresholds' do
      it 'works with 3% threshold' do
        allow(AlgoConfig).to receive(:fetch).and_return(risk: { tp_pct: 0.03, trailing: { activation_pct: 1.0 } })
        position_data.pnl_pct = 0.05
        result = rule.evaluate(context)
        expect(result.exit?).to be true
      end

      it 'works with 10% threshold' do
        allow(AlgoConfig).to receive(:fetch).and_return(risk: { tp_pct: 0.10, trailing: { activation_pct: 1.0 } })
        position_data.pnl_pct = 0.07
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
