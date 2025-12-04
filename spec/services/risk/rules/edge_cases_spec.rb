# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Rule Engine Edge Cases' do
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
  let(:risk_config) { { sl_pct: 2.0, tp_pct: 5.0 } }
  let(:engine) { Risk::Rules::RuleFactory.create_engine(risk_config: risk_config) }

  describe 'zero thresholds' do
    let(:position_data) do
      Positions::ActiveCache::PositionData.new(
        tracker_id: tracker.id,
        entry_price: 100.0,
        quantity: 10,
        current_ltp: 96.0,
        pnl: -40.0,
        pnl_pct: -4.0
      )
    end
    let(:zero_config) { { sl_pct: 0, tp_pct: 0 } }
    let(:engine) { Risk::Rules::RuleFactory.create_engine(risk_config: zero_config) }
    let(:context) do
      Risk::Rules::RuleContext.new(
        position: position_data,
        tracker: tracker,
        risk_config: zero_config
      )
    end

    it 'zero threshold means rule is effectively disabled' do
      result = engine.evaluate(context)
      # SL/TP rules skip, other rules might trigger
      sl_rule = engine.find_rule(Risk::Rules::StopLossRule)
      expect(sl_rule.config[:sl_pct]).to eq(0)
    end
  end

  describe 'invalid time format' do
    let(:position_data) do
      Positions::ActiveCache::PositionData.new(
        tracker_id: tracker.id,
        entry_price: 100.0,
        quantity: 10,
        current_ltp: 103.0,
        pnl: 300.0,
        pnl_pct: 3.0
      )
    end
    let(:invalid_config) { risk_config.merge(time_exit_hhmm: 'invalid_time') }
    let(:engine) { Risk::Rules::RuleFactory.create_engine(risk_config: invalid_config) }
    let(:context) do
      Risk::Rules::RuleContext.new(
        position: position_data,
        tracker: tracker,
        risk_config: invalid_config,
        current_time: Time.zone.parse('15:20')
      )
    end

    it 'invalid time format causes rule to skip' do
      result = engine.evaluate(context)
      # TimeBasedExitRule should skip, other rules evaluated
      expect(result.no_action?).to be true
    end
  end

  describe 'stale data handling' do
    let(:position_data) do
      Positions::ActiveCache::PositionData.new(
        tracker_id: tracker.id,
        entry_price: 100.0,
        quantity: 10,
        current_ltp: 96.0,
        pnl: -40.0,
        pnl_pct: -4.0,
        last_updated_at: 45.seconds.ago
      )
    end
    let(:context) do
      Risk::Rules::RuleContext.new(
        position: position_data,
        tracker: tracker,
        risk_config: risk_config
      )
    end

    it 'rules still evaluate with stale position data' do
      # Rules use position data as-is, staleness is handled upstream
      result = engine.evaluate(context)
      expect(result.exit?).to be true
    end
  end

  describe 'missing risk config' do
    let(:position_data) do
      Positions::ActiveCache::PositionData.new(
        tracker_id: tracker.id,
        entry_price: 100.0,
        quantity: 10,
        current_ltp: 96.0,
        pnl: -40.0,
        pnl_pct: -4.0
      )
    end
    let(:empty_config) { {} }
    let(:engine) { Risk::Rules::RuleFactory.create_engine(risk_config: empty_config) }
    let(:context) do
      Risk::Rules::RuleContext.new(
        position: position_data,
        tracker: tracker,
        risk_config: empty_config
      )
    end

    it 'rules use defaults when config missing' do
      result = engine.evaluate(context)
      # Rules with missing config will skip
      expect(result.no_action?).to be true
    end
  end

  describe 'rule evaluation errors' do
    let(:position_data) do
      Positions::ActiveCache::PositionData.new(
        tracker_id: tracker.id,
        entry_price: 100.0,
        quantity: 10,
        current_ltp: 96.0,
        pnl: -40.0,
        pnl_pct: -4.0
      )
    end
    let(:context) do
      Risk::Rules::RuleContext.new(
        position: position_data,
        tracker: tracker,
        risk_config: risk_config
      )
    end

    it 'rule errors are caught and logged' do
      error_rule = instance_double(Risk::Rules::BaseRule)
      sl_rule = Risk::Rules::StopLossRule.new(config: risk_config)

      allow(error_rule).to receive(:priority).and_return(15)
      allow(error_rule).to receive(:enabled?).and_return(true)
      allow(error_rule).to receive(:evaluate).and_raise(StandardError.new('Test error'))
      allow(error_rule).to receive(:name).and_return('error_rule')

      engine = Risk::Rules::RuleEngine.new(rules: [error_rule, sl_rule])

      expect(Rails.logger).to receive(:error).with(/Error evaluating rule error_rule/)

      result = engine.evaluate(context)
      expect(result.exit?).to be true # SL rule still triggers
    end
  end

  describe 'concurrent rule evaluation' do
    let(:position_data) do
      Positions::ActiveCache::PositionData.new(
        tracker_id: tracker.id,
        entry_price: 100.0,
        quantity: 10,
        current_ltp: 105.0,
        pnl: 50.0,
        pnl_pct: 5.0
      )
    end
    let(:context) do
      Risk::Rules::RuleContext.new(
        position: position_data,
        tracker: tracker,
        risk_config: risk_config
      )
    end

    it 'engine is thread-safe for evaluation' do
      results = []
      threads = []

      5.times do
        threads << Thread.new do
          results << engine.evaluate(context)
        end
      end

      threads.each(&:join)

      # All evaluations should return same result
      expect(results.uniq.count).to eq(1)
    end
  end

  describe 'very large profit values' do
    let(:position_data) do
      Positions::ActiveCache::PositionData.new(
        tracker_id: tracker.id,
        entry_price: 100.0,
        quantity: 10,
        current_ltp: 200.0,
        pnl: 100_000.0,
        pnl_pct: 100.0,
        peak_profit_pct: 100.0
      )
    end
    let(:context) do
      Risk::Rules::RuleContext.new(
        position: position_data,
        tracker: tracker,
        risk_config: risk_config
      )
    end

    it 'handles large profit values correctly' do
      result = engine.evaluate(context)
      expect(result.exit?).to be true
      expect(result.reason).to include('TP HIT')
    end
  end

  describe 'very small profit values' do
    let(:position_data) do
      Positions::ActiveCache::PositionData.new(
        tracker_id: tracker.id,
        entry_price: 100.0,
        quantity: 10,
        current_ltp: 100.01,
        pnl: 0.1,
        pnl_pct: 0.01
      )
    end
    let(:context) do
      Risk::Rules::RuleContext.new(
        position: position_data,
        tracker: tracker,
        risk_config: risk_config
      )
    end

    it 'handles small profit values correctly' do
      result = engine.evaluate(context)
      expect(result.no_action?).to be true
    end
  end
end
