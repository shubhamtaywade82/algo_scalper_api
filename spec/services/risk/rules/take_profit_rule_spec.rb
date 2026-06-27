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
  let(:position) { OpenStruct.new(pnl_pct: pnl_pct) }
  let(:pnl_pct) { 0.07 }
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

  before do
    allow(Live::UnifiedExitChecker).to receive(:exit_config_for).and_return({ take_profit: 0.05 })
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

    it 'skips when pnl is missing' do
      missing_context = Risk::Rules::RuleContext.new(
        position: OpenStruct.new(pnl_pct: nil),
        tracker: tracker,
        tracker_snapshot: {},
        risk_config: risk_config
      )

      expect(rule.evaluate(missing_context)).to be_skip
    end
  end
end
