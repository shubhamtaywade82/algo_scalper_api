# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Risk::Rules::PercentagePnlRule do
  let(:config) do
    {
      percentage_pnl_exit: {
        enabled: true,
        target_pct: 15.0
      }
    }
  end
  let(:rule) { described_class.new(config: config) }
  let(:tracker) { instance_double(PositionTracker, active: true) }
  let(:context) do
    instance_double(
      Risk::Rules::RuleContext,
      active?: true,
      pnl_pct: pnl_pct,
      risk_config: config
    )
  end

  describe '#evaluate' do
    context 'when PnL is below target' do
      let(:pnl_pct) { BigDecimal('0.10') } # 10%

      it 'returns no_action_result' do
        result = rule.evaluate(context)
        expect(result.exit?).to be false
        expect(result.action).to eq(:no_action)
      end
    end

    context 'when PnL reaches target' do
      let(:pnl_pct) { BigDecimal('0.15') } # 15%

      it 'returns exit_result' do
        result = rule.evaluate(context)
        expect(result.exit?).to be true
        expect(result.reason).to include('PERCENTAGE_PNL_EXIT HIT 15.0%')
      end
    end

    context 'when PnL exceeds target' do
      let(:pnl_pct) { BigDecimal('0.20') } # 20%

      it 'returns exit_result' do
        result = rule.evaluate(context)
        expect(result.exit?).to be true
        expect(result.reason).to include('PERCENTAGE_PNL_EXIT HIT 20.0%')
      end
    end

    context 'with decimal target in config' do
      let(:config) do
        {
          percentage_pnl_exit: {
            enabled: true,
            target_pct: 0.15 # 15% as decimal
          }
        }
      end
      let(:pnl_pct) { BigDecimal('0.16') }

      it 'correctly identifies threshold and triggers exit' do
        result = rule.evaluate(context)
        expect(result.exit?).to be true
      end
    end

    context 'when disabled' do
      let(:pnl_pct) { BigDecimal('0.20') }

      it 'is handled by the rule engine, but here we check the rule logic' do
        # BaseRule#enabled? check is usually done by the engine
        # but the rule itself should still work if called
        result = rule.evaluate(context)
        expect(result.exit?).to be true
      end
    end
  end
end
