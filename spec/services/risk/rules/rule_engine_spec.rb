# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Risk::Rules::RuleEngine do
  before do
    hub = Live::MarketFeedHub.instance
    allow(hub).to receive_messages(subscribe: nil, subscribed?: true)
  end

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
  let(:risk_config) do
    {
      sl_pct: 0.02,
      tp_pct: 0.05
    }
  end
  let(:context) do
    Risk::Rules::RuleContext.new(
      position: position_data,
      tracker: tracker,
      risk_config: risk_config
    )
  end

  describe '#initialize' do
    it 'sorts rules by priority' do
      rule1 = Risk::Rules::StopLossRule.new(config: {})
      rule2 = Risk::Rules::TakeProfitRule.new(config: {})
      rule3 = Risk::Rules::SessionEndRule.new(config: {})

      engine = described_class.new(rules: [rule2, rule1, rule3])
      expect(engine.rules.map(&:class)).to eq(
        [Risk::Rules::SessionEndRule, Risk::Rules::StopLossRule, Risk::Rules::TakeProfitRule]
      )
    end
  end

  describe '#evaluate' do
    context 'when position is exited' do
      before do
        tracker.update(status: 'exited')
      end

      it 'returns skip result' do
        engine = described_class.new(rules: [])
        result = engine.evaluate(context)
        expect(result.skip?).to be true
      end
    end

    context 'priority-based evaluation' do
      it 'evaluates rules in priority order' do
        sl_rule = Risk::Rules::StopLossRule.new(config: risk_config)
        tp_rule = Risk::Rules::TakeProfitRule.new(config: risk_config)

        engine = described_class.new(rules: [tp_rule, sl_rule])

        # Stop loss should trigger first (higher priority)
        result = engine.evaluate(context)
        expect(result.exit?).to be true
        expect(result.reason).to include('SL HIT')
      end

      it 'stops evaluation when first rule triggers exit' do
        sl_rule = instance_double(Risk::Rules::StopLossRule)
        tp_rule = instance_double(Risk::Rules::TakeProfitRule)

        allow(sl_rule).to receive_messages(priority: 20, enabled?: true,
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
        # Rules read thresholds from RuleContext#risk_config, not the rule instance.
        zero_sl_config = risk_config.merge(sl_pct: 0)
        ctx = Risk::Rules::RuleContext.new(
          position: position_data,
          tracker: tracker,
          risk_config: zero_sl_config
        )
        sl_rule = Risk::Rules::StopLossRule.new(config: {})
        tp_rule = Risk::Rules::TakeProfitRule.new(config: risk_config)

        engine = described_class.new(rules: [sl_rule, tp_rule])
        result = engine.evaluate(ctx)

        # SL rule skipped (sl_pct 0), TP rule evaluated but doesn't trigger
        expect(result.no_action?).to be true
      end
    end

    context 'with skip results' do
      it 'continues to next rule when rule returns skip' do
        skip_rule = instance_double(Risk::Rules::BaseRule)
        sl_rule = Risk::Rules::StopLossRule.new(config: risk_config)

        allow(skip_rule).to receive_messages(priority: 15, enabled?: true, evaluate: Risk::Rules::RuleResult.skip,
                                             name: 'skip_rule')

        engine = described_class.new(rules: [skip_rule, sl_rule])
        result = engine.evaluate(context)

        expect(result.exit?).to be true
        expect(result.reason).to include('SL HIT')
      end
    end

    context 'error handling' do
      it 'catches errors and continues to next rule' do
        error_rule = instance_double(Risk::Rules::BaseRule)
        sl_rule = Risk::Rules::StopLossRule.new(config: risk_config)

        allow(error_rule).to receive(:evaluate).and_raise(StandardError.new('Test error'))
        allow(error_rule).to receive_messages(priority: 15, enabled?: true, name: 'error_rule')

        engine = described_class.new(rules: [error_rule, sl_rule])
        result = engine.evaluate(context)

        expect(result.exit?).to be true
        expect(result.reason).to include('SL HIT')
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
        engine = described_class.new(rules: [tp_rule])

        # PnL is -4%, TP threshold is 5%, so no match
        result = engine.evaluate(context)
        expect(result.no_action?).to be true
      end
    end

    context 'combined scenarios' do
      it 'session end overrides take profit' do
        session_rule = Risk::Rules::SessionEndRule.new(config: {})
        tp_rule = Risk::Rules::TakeProfitRule.new(config: risk_config)

        position_data.pnl_pct = 0.10 # TP would trigger (10% as decimal)

        allow(TradingSession::Service).to receive(:should_force_exit?).and_return(
          { should_exit: true }
        )

        engine = described_class.new(rules: [session_rule, tp_rule])
        result = engine.evaluate(context)

        expect(result.exit?).to be true
        expect(result.reason).to include('session end')
      end

      it 'stop loss overrides take profit' do
        sl_rule = Risk::Rules::StopLossRule.new(config: risk_config)
        tp_rule = Risk::Rules::TakeProfitRule.new(config: risk_config)

        # Both conditions could be met, but SL has higher priority
        position_data.pnl_pct = -0.04 # SL triggers
        position_data.current_ltp = 96.0

        engine = described_class.new(rules: [sl_rule, tp_rule])
        result = engine.evaluate(context)

        expect(result.exit?).to be true
        expect(result.reason).to include('SL HIT')
      end
    end
  end

  describe '#add_rule' do
    it 'adds rule and re-sorts by priority' do
      engine = described_class.new(rules: [])
      rule1 = Risk::Rules::TakeProfitRule.new(config: {})
      rule2 = Risk::Rules::StopLossRule.new(config: {})

      engine.add_rule(rule1)
      engine.add_rule(rule2)

      expect(engine.rules.map(&:class)).to eq(
        [Risk::Rules::StopLossRule, Risk::Rules::TakeProfitRule]
      )
    end
  end

  describe '#remove_rule' do
    it 'removes rule by class' do
      sl_rule = Risk::Rules::StopLossRule.new(config: {})
      tp_rule = Risk::Rules::TakeProfitRule.new(config: {})

      engine = described_class.new(rules: [sl_rule, tp_rule])
      engine.remove_rule(Risk::Rules::StopLossRule)

      expect(engine.rules.map(&:class)).to eq([Risk::Rules::TakeProfitRule])
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
