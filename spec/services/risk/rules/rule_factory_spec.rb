# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Risk::Rules::RuleFactory do
  let(:risk_config) do
    {
      sl_pct: 2.0,
      tp_pct: 5.0,
      secure_profit_threshold_rupees: 1000.0,
      secure_profit_drawdown_pct: 3.0
    }
  end

  describe '.create_engine' do
    it 'creates engine with all default rules' do
      engine = described_class.create_engine(risk_config: risk_config)

      expect(engine).to be_a(Risk::Rules::RuleEngine)
      expect(engine.rules.count).to eq(9)

      rule_classes = engine.rules.map(&:class)
      expect(rule_classes).to include(Risk::Rules::SessionEndRule)
      expect(rule_classes).to include(Risk::Rules::StopLossRule)
      expect(rule_classes).to include(Risk::Rules::TakeProfitRule)
      expect(rule_classes).to include(Risk::Rules::BracketLimitRule)
      expect(rule_classes).to include(Risk::Rules::SecureProfitRule)
      expect(rule_classes).to include(Risk::Rules::TimeBasedExitRule)
      expect(rule_classes).to include(Risk::Rules::PeakDrawdownRule)
      expect(rule_classes).to include(Risk::Rules::TrailingStopRule)
      expect(rule_classes).to include(Risk::Rules::UnderlyingExitRule)
    end

    it 'sorts rules by priority' do
      engine = described_class.create_engine(risk_config: risk_config)
      priorities = engine.rules.map(&:priority)

      expect(priorities).to eq(priorities.sort)
    end

    it 'passes config to all rules' do
      engine = described_class.create_engine(risk_config: risk_config)
      sl_rule = engine.find_rule(Risk::Rules::StopLossRule)

      expect(sl_rule.config).to eq(risk_config)
    end
  end

  describe '.create_custom_engine' do
    it 'creates engine with custom rules only' do
      custom_rule = Risk::Rules::StopLossRule.new(config: risk_config)

      engine = described_class.create_custom_engine(
        rules: [custom_rule],
        include_defaults: false,
        risk_config: risk_config
      )

      expect(engine.rules.count).to eq(1)
      expect(engine.rules.first).to eq(custom_rule)
    end

    it 'creates engine with custom rules plus defaults' do
      custom_rule = Risk::Rules::StopLossRule.new(config: risk_config)

      engine = described_class.create_custom_engine(
        rules: [custom_rule],
        include_defaults: true,
        risk_config: risk_config
      )

      expect(engine.rules.count).to eq(10) # 9 defaults + 1 custom
      expect(engine.rules).to include(custom_rule)
    end

    it 'handles empty custom rules array' do
      engine = described_class.create_custom_engine(
        rules: [],
        include_defaults: true,
        risk_config: risk_config
      )

      expect(engine.rules.count).to eq(9) # Just defaults
    end
  end
end
