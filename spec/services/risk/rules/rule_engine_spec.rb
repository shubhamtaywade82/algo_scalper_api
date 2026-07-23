# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Risk::Rules::RuleEngine do
  let(:tracker) { instance_double(PositionTracker, active?: true, entry_price: 100.0, quantity: 10) }
  let(:position) { OpenStruct.new(pnl_pct: -0.04, pnl: -40.0, current_ltp: 96.0) }
  let(:tracker_snapshot) { { pnl_pct: -0.04, ltp: 96.0, pnl: -40.0, hwm_pnl: 0.0 } }
  let(:risk_config) { { sl_pct: 0.02, tp_pct: 0.05 } }
  let(:context) do
    Risk::Rules::RuleContext.new(
      position: position,
      tracker: tracker,
      tracker_snapshot: tracker_snapshot,
      risk_config: risk_config
    )
  end

  describe '#initialize' do
    it 'sorts rules by priority' do
      rule1 = Risk::Rules::StopLossRule.new(config: {})
      rule2 = Risk::Rules::TakeProfitRule.new(config: {})

      engine = described_class.new(rules: [rule2, rule1])
      expect(engine.rules.map(&:class)).to eq(
        [Risk::Rules::StopLossRule, Risk::Rules::TakeProfitRule]
      )
    end
  end

  describe '#evaluate' do
    context 'when position is exited' do
      let(:tracker) { instance_double(PositionTracker, active?: false) }

      it 'returns skip result' do
        engine = described_class.new(rules: [])
        result = engine.evaluate(context)
        expect(result.skip?).to be true
      end
    end

    context 'when evaluating by priority' do
      it 'evaluates rules in priority order' do
        sl_rule = Risk::Rules::StopLossRule.new(config: risk_config)
        tp_rule = Risk::Rules::TakeProfitRule.new(config: risk_config)

        allow(Live::UnifiedExitChecker).to receive(:loss_limit_hit?).and_return(true)

        engine = described_class.new(rules: [tp_rule, sl_rule])
        result = engine.evaluate(context)

        expect(result.exit?).to be true
        expect(result.reason).to eq('STOP_LOSS')
      end

      it 'stops evaluation when first rule triggers exit' do
        sl_rule = instance_double(Risk::Rules::StopLossRule)
        tp_rule = instance_double(Risk::Rules::TakeProfitRule)

        allow(sl_rule).to receive_messages(priority: 20, enabled?: true, name: 'stop_loss',
                                           evaluate: Risk::Rules::RuleResult.exit(reason: 'SL'))
        allow(tp_rule).to receive_messages(priority: 30, enabled?: true,
                                           evaluate: Risk::Rules::RuleResult.exit(reason: 'TP'))

        engine = described_class.new(rules: [sl_rule, tp_rule])
        result = engine.evaluate(context)

        expect(result.exit?).to be true
        expect(result.reason).to eq('SL')
        expect(tp_rule).not_to have_received(:evaluate)
      end
    end

    context 'with disabled rules' do
      it 'skips disabled rules' do
        sl_rule = Risk::Rules::StopLossRule.new(config: { enabled: false })
        tp_rule = Risk::Rules::TakeProfitRule.new(config: risk_config)

        allow(Live::UnifiedExitChecker).to receive(:exit_config_for).and_return({ take_profit: 0.05 })

        engine = described_class.new(rules: [sl_rule, tp_rule])
        result = engine.evaluate(context)

        expect(result.no_action?).to be true
      end
    end

    context 'with skip results' do
      it 'continues to next rule when rule returns skip' do
        skip_rule = instance_double(Risk::Rules::BaseRule)
        sl_rule = Risk::Rules::StopLossRule.new(config: risk_config)

        allow(skip_rule).to receive_messages(priority: 15, enabled?: true, evaluate: Risk::Rules::RuleResult.skip,
                                             name: 'skip_rule')
        allow(Live::UnifiedExitChecker).to receive(:loss_limit_hit?).and_return(true)

        engine = described_class.new(rules: [skip_rule, sl_rule])
        result = engine.evaluate(context)

        expect(result.exit?).to be true
        expect(result.reason).to eq('STOP_LOSS')
      end
    end

    context 'when a rule raises an error' do
      it 'catches errors and continues to next rule' do
        error_rule = instance_double(Risk::Rules::BaseRule)
        sl_rule = Risk::Rules::StopLossRule.new(config: risk_config)

        allow(error_rule).to receive(:evaluate).and_raise(StandardError.new('Test error'))
        allow(error_rule).to receive_messages(priority: 15, enabled?: true, name: 'error_rule')
        allow(Live::UnifiedExitChecker).to receive(:loss_limit_hit?).and_return(true)

        engine = described_class.new(rules: [error_rule, sl_rule])
        result = engine.evaluate(context)

        expect(result.exit?).to be true
        expect(result.reason).to eq('STOP_LOSS')
      end

      it 'logs errors' do
        error_rule = instance_double(Risk::Rules::BaseRule)

        allow(error_rule).to receive(:evaluate).and_raise(StandardError.new('Test error'))
        allow(error_rule).to receive_messages(priority: 15, enabled?: true, name: 'error_rule')

        allow(Rails.logger).to receive(:error)

        engine = described_class.new(rules: [error_rule])
        engine.evaluate(context)

        expect(Rails.logger).to have_received(:error).with(/Error evaluating rule error_rule/)
      end
    end

    context 'when no rule matches' do
      it 'returns no_action' do
        tp_rule = Risk::Rules::TakeProfitRule.new(config: risk_config)
        allow(Live::UnifiedExitChecker).to receive(:exit_config_for).and_return({ take_profit: 0.05 })

        engine = described_class.new(rules: [tp_rule])
        result = engine.evaluate(context)

        expect(result.no_action?).to be true
      end
    end

    context 'when stop loss and take profit both match' do
      it 'stop loss overrides take profit' do
        sl_rule = Risk::Rules::StopLossRule.new(config: risk_config)
        tp_rule = Risk::Rules::TakeProfitRule.new(config: risk_config)

        allow(Live::UnifiedExitChecker).to receive(:loss_limit_hit?).and_return(true)

        engine = described_class.new(rules: [sl_rule, tp_rule])
        result = engine.evaluate(context)

        expect(result.exit?).to be true
        expect(result.reason).to eq('STOP_LOSS')
      end
    end
  end

  describe '#find_rule' do
    it 'finds rule by class' do
      sl_rule = Risk::Rules::StopLossRule.new(config: {})
      tp_rule = Risk::Rules::TakeProfitRule.new(config: {})

      engine = described_class.new(rules: [sl_rule, tp_rule])
      found = engine.find_rule(Risk::Rules::StopLossRule)

      expect(found).to eq(sl_rule)
    end

    it 'returns nil when rule not found' do
      engine = described_class.new(rules: [])
      found = engine.find_rule(Risk::Rules::StopLossRule)

      expect(found).to be_nil
    end
  end

  describe '#enabled_rules' do
    it 'returns only enabled rules' do
      sl_rule = Risk::Rules::StopLossRule.new(config: { enabled: false })
      tp_rule = Risk::Rules::TakeProfitRule.new(config: {})

      engine = described_class.new(rules: [sl_rule, tp_rule])
      enabled = engine.enabled_rules

      expect(enabled).to eq([tp_rule])
    end
  end
end
