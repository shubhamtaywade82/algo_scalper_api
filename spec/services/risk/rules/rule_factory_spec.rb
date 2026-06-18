# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Risk::Rules::RuleFactory do
  let(:risk_config) do
    {
      adaptive_trailing: {
        enabled: true,
        supertrend_flip_exit: false,
        counter_candles: 0
      }
    }
  end

  describe '.exit_rules' do
    it 'returns only the prop-desk adaptive trail rule' do
      rules = described_class.exit_rules(risk_config)
      rule_classes = rules.map(&:class)

      expect(rule_classes).to eq([Risk::Rules::AdaptiveTrailRule])
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
      trail_rule = engine.find_rule(Risk::Rules::AdaptiveTrailRule)

      expect(trail_rule.config).to eq(risk_config)
    end
  end
end
