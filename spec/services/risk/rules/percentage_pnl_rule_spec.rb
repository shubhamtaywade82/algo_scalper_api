# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Risk::Rules::PercentagePnlRule do
  let(:config) { { enabled: true } }
  let(:rule) { described_class.new(config: config) }
  let(:tracker) { instance_double(PositionTracker, id: 1, entry_price: 100.0, quantity: 10) }
  let(:snapshot) { { pnl_pct: pnl_pct, pnl: 10.0, ltp: 110.0 } }
  let(:context) do
    instance_double(
      Risk::Rules::RuleContext,
      active?: true,
      tracker: tracker,
      tracker_snapshot: snapshot
    )
  end

  before do
    # Pin the rule's static-target semantics: this spec exercises the rule
    # plumbing (below/reaches/exceeds target, snapshot fallback) against a known
    # 5% target. The fee-aware floor (risk.scalp_exit — shipped enabled in
    # algo.yml) raises targets per-position and has its own dedicated specs
    # (scalp/fee_aware_exit_targets_spec + the unified_exit_checker wiring
    # specs); leaving it out of this stub keeps those concerns decoupled.
    allow(AlgoConfig).to receive(:fetch).and_return(
      risk: { percentage_pnl_exit: { enabled: true, target_pct: 0.05 } }
    )
  end

  describe '#evaluate' do
    context 'when PnL is below target' do
      let(:pnl_pct) { BigDecimal('0.03') } # 3%

      it 'returns no_action_result' do
        result = rule.evaluate(context)
        expect(result.exit?).to be false
        expect(result.action).to eq(:no_action)
      end
    end

    context 'when PnL reaches target' do
      let(:pnl_pct) { BigDecimal('0.05') } # 5% target (algo.yml)

      it 'returns exit_result with percentage display in reason' do
        result = rule.evaluate(context)
        expect(result.exit?).to be true
        expect(result.reason).to include('PERCENTAGE_PNL_EXIT')
        expect(result.reason).to include('5.0%')
      end
    end

    context 'when PnL exceeds target' do
      let(:pnl_pct) { BigDecimal('0.20') } # 20%

      it 'returns exit_result showing actual pnl and target' do
        result = rule.evaluate(context)
        expect(result.exit?).to be true
        expect(result.reason).to include('PERCENTAGE_PNL_EXIT')
        expect(result.reason).to include('20.0%')
      end
    end

    context 'when no snapshot available' do
      let(:snapshot) { nil }

      it 'falls back to Redis PnL cache' do
        allow(Live::RedisPnlCache.instance).to receive(:fetch_pnl).with(tracker.id).and_return(
          pnl_pct: 0.10, pnl: 10.0, ltp: 110.0
        )

        result = rule.evaluate(context)
        expect(result.exit?).to be true
      end

      it 'returns no_action when Redis has no data' do
        allow(Live::RedisPnlCache.instance).to receive(:fetch_pnl).with(tracker.id).and_return(nil)

        result = rule.evaluate(context)
        expect(result.no_action?).to be true
      end
    end
  end
end
