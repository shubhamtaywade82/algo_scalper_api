# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Risk::Rules::RuleFactory do
  let(:risk_config) do
    {
      sl_pct: 0.10,
      tp_pct: 0.45,
      secure_profit_threshold_rupees: 600.0,
      secure_profit_drawdown_pct: 0.025
    }
  end

  describe '.exit_rules' do
    it 'includes prop-desk give-back protection rules' do
      rules = described_class.exit_rules(risk_config)
      rule_classes = rules.map(&:class)

      # ProfitFloorExitRule, PeakDrawdownRule, and AdaptiveTrailRule were deleted —
      # confirmed duplicates of already-live logic in exit_enforcement.rb/trailing_engine.rb/
      # unified_exit_checker.rb.
      expect(rule_classes).to include(
        Risk::Rules::VixForceExitRule,
        Risk::Rules::DteZeroThetaFlatExitRule,
        Risk::Rules::GreenTradeCapRule,
        Risk::Rules::SecureProfitRule,
        Risk::Rules::FastProfitLockRule
      )
    end
  end

  describe '.create_engine' do
    it 'creates engine with rules sorted by priority' do
      engine = described_class.create_engine(risk_config: risk_config)

      expect(engine).to be_a(Risk::Rules::RuleEngine)
      priorities = engine.rules.map(&:priority)
      expect(priorities).to eq(priorities.sort)
    end

    it 'passes config to all rules' do
      engine = described_class.create_engine(risk_config: risk_config)
      sl_rule = engine.find_rule(Risk::Rules::StopLossRule)

      expect(sl_rule.config).to eq(risk_config)
    end
  end
end
