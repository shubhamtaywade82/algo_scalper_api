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
      pnl_pct: -0.04
    )
  end
  let(:sl_pct) { 0.02 }
  let(:risk_config) { { sl_pct: sl_pct } }
  let(:context) do
    Risk::Rules::RuleContext.new(
      position: position_data,
      tracker: tracker,
      risk_config: risk_config,
      tracker_snapshot: { pnl_pct: position_data.pnl_pct }
    )
  end
  let(:rule) { described_class.new(config: risk_config) }

  before do
    # UnifiedExitChecker.exit_config caches on class-level instance variables
    # with a 30s TTL - reset it so each example's AlgoConfig.fetch stub takes
    # effect instead of a stale config from a previous example.
    Live::UnifiedExitChecker.instance_variable_set(:@exit_config, nil)
    Live::UnifiedExitChecker.instance_variable_set(:@exit_config_expires_at, nil)
    allow(AlgoConfig).to receive(:fetch).and_return(risk: { sl_pct: sl_pct })
  end

  describe '#evaluate' do
    context 'when stop loss is hit' do
      it 'returns exit result when PnL drops below threshold' do
        result = rule.evaluate(context)
        expect(result.exit?).to be true
        expect(result.reason).to eq('STOP_LOSS')
        expect(result.metadata[:pnl_pct]).to eq(-4.0)
      end

      it 'triggers exit when PnL exactly equals threshold' do
        position_data.pnl_pct = -0.02
        result = rule.evaluate(context)
        expect(result.exit?).to be true
      end

      it 'triggers exit when PnL is worse than threshold' do
        position_data.pnl_pct = -0.05
        result = rule.evaluate(context)
        expect(result.exit?).to be true
      end
    end

    context 'when stop loss is not hit' do
      it 'returns no_action when PnL is above threshold' do
        position_data.pnl_pct = -0.01
        result = rule.evaluate(context)
        expect(result.no_action?).to be true
      end

      it 'returns no_action when PnL is positive' do
        position_data.pnl_pct = 0.01
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

    context 'when stop loss threshold is zero' do
      let(:sl_pct) { 0 }

      it 'exits immediately on any loss when sl_pct is 0 (0% threshold, not disabled)' do
        # exit_config treats 0 as a real configured value (pnl_pct <= -0),
        # not as "disabled" - any negative pnl_pct triggers immediately.
        result = rule.evaluate(context)
        expect(result.exit?).to be true
      end
    end

    context 'with different thresholds' do
      it 'works with 1% threshold' do
        allow(AlgoConfig).to receive(:fetch).and_return(risk: { sl_pct: 0.01 })
        position_data.pnl_pct = -0.015
        result = rule.evaluate(context)
        expect(result.exit?).to be true
      end

      it 'works with 5% threshold' do
        allow(AlgoConfig).to receive(:fetch).and_return(risk: { sl_pct: 0.05 })
        position_data.pnl_pct = -0.03
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
