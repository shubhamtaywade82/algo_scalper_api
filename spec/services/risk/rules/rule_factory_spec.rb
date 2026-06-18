# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Risk::Rules::RuleFactory do
  let(:risk_config) { { sl_pct: 0.15, tp_pct: 0.45 } }

  describe '.create_engine' do
    it 'creates the stock options-buying exit engine' do
      engine = described_class.create_engine(risk_config: risk_config)

      expect(engine).to be_a(Risk::Rules::RuleEngine)
      expect(engine.rules.map(&:class)).to eq([
                                                Risk::Rules::StopLossRule,
                                                Risk::Rules::AdaptiveTrailRule,
                                                Risk::Rules::TakeProfitRule,
                                                Risk::Rules::TimeBasedExitRule
                                              ])
    end

    it 'passes config to all rules' do
      engine = described_class.create_engine(risk_config: risk_config)

      expect(engine.rules.map(&:config)).to all(eq(risk_config))
    end
  end
end
