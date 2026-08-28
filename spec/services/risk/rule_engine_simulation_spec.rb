# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Risk Rule Engine - Full Position Simulation (Integration)', type: :service do
  # Test configuration
  let(:lot_size) { 75 }
  let(:lots) { 4 }
  let(:qty) { lot_size * lots } # 300 units
  let(:entry_premium) { BigDecimal('100.0') }
  let(:buy_value) { (entry_premium * qty).to_f } # 100 * 300 = 30,000

  # Risk configuration for tests (percentages in decimal: 0.20 = 20%)
  let(:risk_config) do
    {
      sl_pct: 0.20,
      tp_pct: 0.60,
      secure_profit_enabled: true,
      secure_profit_threshold_rupees: 1000.0,
      secure_profit_drawdown_pct: 0.03,
      time_exit_hhmm: '15:20',
      min_profit_rupees: 200.0,
      exit: { time_based: { enabled: true, exit_time: '15:20' } }
    }
  end

  # Real components
  let(:rule_engine) { Risk::Rules::RuleFactory.create_engine(risk_config: risk_config) }
  let(:exit_engine) { double('ExitEngine') }

  # Test position setup
  let(:instrument) { create(:instrument, :nifty_future) }
  let(:tracker) do
    create(
      :position_tracker,
      instrument: instrument,
      status: 'active',
      entry_price: entry_premium.to_f,
      quantity: qty
    )
  end

  def build_position(pnl:, pnl_pct:, ltp:, peak_profit_pct: nil)
    Positions::PositionData.new(
      tracker_id: tracker.id,
      security_id: tracker.security_id,
      segment: tracker.segment,
      entry_price: tracker.entry_price,
      quantity: tracker.quantity,
      current_ltp: ltp,
      pnl: pnl,
      pnl_pct: pnl_pct,
      peak_profit_pct: peak_profit_pct || pnl_pct,
      last_updated_at: Time.current
    )
  end

  def context_for(position, snapshot: nil, config: risk_config, time: Time.current)
    Risk::Rules::RuleContext.new(
      position: position,
      tracker: tracker,
      risk_config: config,
      tracker_snapshot: snapshot,
      current_time: time
    )
  end

  describe 'Stop Loss Exit' do
    it 'exits when PnL drops to -20% (stop loss threshold)' do
      position = build_position(pnl: -0.20 * buy_value, pnl_pct: -0.20, ltp: 80.0)
      snapshot = { pnl_pct: -0.20, pnl: -0.20 * buy_value, ltp: 80.0 }

      result = rule_engine.evaluate(context_for(position, snapshot: snapshot))
      expect(result.exit?).to be true
      expect(result.reason).to include('STOP_LOSS')
    end

    it 'does not exit when loss is less than stop loss threshold' do
      position = build_position(pnl: -0.05 * buy_value, pnl_pct: -0.05, ltp: 95.0)
      snapshot = { pnl_pct: -0.05, pnl: -0.05 * buy_value, ltp: 95.0 }

      result = rule_engine.evaluate(context_for(position, snapshot: snapshot))
      expect(result.no_action?).to be true
    end
  end

  describe 'Take Profit Exit' do
    let(:tp_engine) do
      Risk::Rules::RuleEngine.new(rules: [Risk::Rules::TakeProfitRule.new(config: risk_config)])
    end

    it 'exits when PnL reaches +60% (take profit threshold)' do
      position = build_position(pnl: 0.60 * buy_value, pnl_pct: 0.60, ltp: 160.0)
      snapshot = { pnl_pct: 0.60, pnl: 0.60 * buy_value, ltp: 160.0 }

      result = tp_engine.evaluate(context_for(position, snapshot: snapshot))
      expect(result.exit?).to be true
      expect(result.reason).to include('TAKE_PROFIT')
    end

    it 'does not exit when profit is below take profit threshold' do
      position = build_position(pnl: 0.30 * buy_value, pnl_pct: 0.30, ltp: 130.0)
      snapshot = { pnl_pct: 0.30, pnl: 0.30 * buy_value, ltp: 130.0 }

      result = tp_engine.evaluate(context_for(position, snapshot: snapshot))
      expect(result.no_action?).to be true
    end
  end

  describe 'Secure Profit Rule' do
    let(:secure_engine) do
      Risk::Rules::RuleEngine.new(rules: [Risk::Rules::SecureProfitRule.new(config: risk_config)])
    end

    it 'exits when profit >= ₹1000 and drawdown >= 3% from peak' do
      # Peak at +25%, current at +21% (4% drawdown from peak)
      position = build_position(
        pnl: 0.21 * buy_value, # +₹6,300 (> ₹1000 threshold)
        pnl_pct: 0.21,
        ltp: 121.0,
        peak_profit_pct: 0.25
      )

      result = secure_engine.evaluate(context_for(position))
      expect(result.exit?).to be true
      expect(result.reason).to include('secure_profit_exit')
    end

    it 'does not exit when profit < ₹1000 even with drawdown' do
      position = build_position(
        pnl: 0.02 * buy_value, # +₹600 (< ₹1000 threshold)
        pnl_pct: 0.02,
        ltp: 102.0,
        peak_profit_pct: 0.05
      )

      result = secure_engine.evaluate(context_for(position))
      expect(result.no_action?).to be true
    end

    it 'allows position to ride when profit >= ₹1000 but no drawdown yet' do
      position = build_position(
        pnl: 0.15 * buy_value, # +₹4,500 (> ₹1000)
        pnl_pct: 0.15,
        ltp: 115.0,
        peak_profit_pct: 0.15 # At peak, no drawdown
      )

      result = secure_engine.evaluate(context_for(position))
      expect(result.no_action?).to be true
    end
  end

  describe 'Peak Drawdown Exit' do
    # TrailingStopRule delegates to UnifiedExitChecker's trailing machinery,
    # which is covered by trailing_activation_spec.rb; here we drive it via stubs.
    let(:trailing_engine) do
      Risk::Rules::RuleEngine.new(rules: [Risk::Rules::TrailingStopRule.new(config: risk_config)])
    end

    it 'exits when drawdown >= 5% from peak after trailing activation' do
      position = build_position(pnl: 0.19 * buy_value, pnl_pct: 0.19, ltp: 119.0, peak_profit_pct: 0.25)
      snapshot = { pnl_pct: 0.19, pnl: 0.19 * buy_value, ltp: 119.0, hwm_pnl: 0.25 * buy_value }

      allow(Live::UnifiedExitChecker).to receive(:evaluate_underlying_context)
        .with(tracker, snapshot).and_return(action: :none, multiplier: 1.0)
      allow(Live::UnifiedExitChecker).to receive(:trailing_stop_hit?)
        .with(tracker, snapshot, tightening_multiplier: 1.0).and_return(true)

      result = trailing_engine.evaluate(context_for(position, snapshot: snapshot))
      expect(result.exit?).to be true
      expect(result.reason).to include('TRAILING_STOP')
    end

    it 'does not exit when drawdown < 5% from peak' do
      position = build_position(pnl: 0.22 * buy_value, pnl_pct: 0.22, ltp: 122.0, peak_profit_pct: 0.25)
      snapshot = { pnl_pct: 0.22, pnl: 0.22 * buy_value, ltp: 122.0, hwm_pnl: 0.25 * buy_value }

      allow(Live::UnifiedExitChecker).to receive(:evaluate_underlying_context)
        .with(tracker, snapshot).and_return(action: :none, multiplier: 1.0)
      allow(Live::UnifiedExitChecker).to receive(:trailing_stop_hit?)
        .with(tracker, snapshot, tightening_multiplier: 1.0).and_return(false)

      result = trailing_engine.evaluate(context_for(position, snapshot: snapshot))
      expect(result.no_action?).to be true
    end
  end

  describe 'Time-Based Exit' do
    let(:time_engine) do
      Risk::Rules::RuleEngine.new(rules: [Risk::Rules::TimeBasedExitRule.new(config: risk_config)])
    end

    it 'exits at configured time (15:20) when minimum profit met' do
      position = build_position(pnl: 0.10 * buy_value, pnl_pct: 0.10, ltp: 110.0)

      allow(Live::UnifiedExitChecker).to receive(:time_based_exit?).and_return(true)

      result = time_engine.evaluate(
        context_for(position, time: Time.zone.parse('2024-01-01 15:20:00'))
      )
      expect(result.exit?).to be true
      expect(result.reason).to include('TIME_BASED')
    end

    it 'does not exit when minimum profit not met' do
      position = build_position(pnl: 0.005 * buy_value, pnl_pct: 0.005, ltp: 100.5)

      allow(Live::UnifiedExitChecker).to receive(:time_based_exit?).and_return(false)

      result = time_engine.evaluate(
        context_for(position, time: Time.zone.parse('2024-01-01 15:20:00'))
      )
      expect(result.no_action?).to be true
    end

    it 'does not exit before configured time' do
      position = build_position(pnl: 0.10 * buy_value, pnl_pct: 0.10, ltp: 110.0)

      allow(Live::UnifiedExitChecker).to receive(:time_based_exit?).and_return(false)

      result = time_engine.evaluate(
        context_for(position, time: Time.zone.parse('2024-01-01 15:19:00'))
      )
      expect(result.no_action?).to be true
    end
  end

  describe 'Session End Exit' do
    it 'exits at session end (3:15 PM)' do
      position = build_position(pnl: 0.05 * buy_value, pnl_pct: 0.05, ltp: 105.0)

      allow(TradingSession::Service).to receive(:should_force_exit?).and_return(
        { should_exit: true, reason: 'session_end' }
      )
      session_engine = Risk::Rules::RuleEngine.new(
        rules: [Risk::Rules::SessionEndRule.new(config: risk_config)]
      )

      result = session_engine.evaluate(context_for(position))
      expect(result.exit?).to be true
      expect(result.reason).to include('session end')
    end
  end

  describe 'Underlying Structure Break' do
    it 'exits when underlying structure breaks' do
      position = build_position(pnl: 0.15 * buy_value, pnl_pct: 0.15, ltp: 115.0)
      snapshot = { pnl_pct: 0.15, pnl: 0.15 * buy_value, ltp: 115.0 }

      allow(Live::UnifiedExitChecker).to receive(:check_structure_invalidation)
        .with(tracker, snapshot).and_return(exit: true, reason: 'STRUCTURE_INVALIDATION')
      structure_engine = Risk::Rules::RuleEngine.new(
        rules: [Risk::Rules::StructureInvalidationRule.new(config: risk_config)]
      )

      result = structure_engine.evaluate(context_for(position, snapshot: snapshot))
      expect(result.exit?).to be true
      expect(result.reason).to include('STRUCTURE_INVALIDATION')
    end
  end

  describe 'Stale Data Handling' do
    let(:percentage_engine) do
      Risk::Rules::RuleEngine.new(rules: [Risk::Rules::PercentagePnlRule.new(config: risk_config)])
    end

    it 'uses Redis PnL cache when snapshot is not provided' do
      position = build_position(pnl: 0.10 * buy_value, pnl_pct: 0.10, ltp: 110.0)

      allow(Live::RedisPnlCache.instance).to receive(:fetch_pnl).with(tracker.id).and_return(
        pnl: 0.10 * buy_value, pnl_pct: 0.10, ltp: 110.0, timestamp: Time.current.to_i
      )

      result = percentage_engine.evaluate(context_for(position, snapshot: nil))
      expect(result.exit?).to be true
      expect(result.reason).to include('PERCENTAGE_PNL_EXIT')
    end

    it 'skips evaluation when Redis has no data and no snapshot' do
      position = build_position(pnl: 0.10 * buy_value, pnl_pct: 0.10, ltp: 110.0)

      allow(Live::RedisPnlCache.instance).to receive(:fetch_pnl).with(tracker.id).and_return(nil)

      result = percentage_engine.evaluate(context_for(position, snapshot: nil))
      expect(result.no_action?).to be true
    end
  end

  describe 'Missing Entry Price' do
    it 'does not exit when entry price is missing' do
      position = Positions::PositionData.new(
        tracker_id: tracker.id,
        entry_price: nil,
        quantity: qty,
        current_ltp: 100.0,
        pnl: 0.0,
        pnl_pct: 0.0
      )
      snapshot = { pnl_pct: 0.0, pnl: 0.0, ltp: 100.0 }

      result = rule_engine.evaluate(context_for(position, snapshot: snapshot))
      expect(result.exit?).to be false
    end
  end

  describe 'Disabled Rules' do
    it 'skips evaluation when rule is disabled via config' do
      position = build_position(pnl: -0.25 * buy_value, pnl_pct: -0.25, ltp: 75.0)
      snapshot = { pnl_pct: -0.25, pnl: -0.25 * buy_value, ltp: 75.0 }

      sl_rule = rule_engine.find_rule(Risk::Rules::StopLossRule)
      allow(sl_rule).to receive(:enabled?).and_return(false)

      result = rule_engine.evaluate(context_for(position, snapshot: snapshot))
      expect(result.exit?).to be false
    end
  end

  describe 'Priority Order' do
    let(:sl_tp_engine) do
      Risk::Rules::RuleEngine.new(
        rules: [Risk::Rules::StopLossRule.new(config: risk_config),
                Risk::Rules::TakeProfitRule.new(config: risk_config)]
      )
    end

    it 'evaluates rules in priority order (SL before TP)' do
      position = build_position(pnl: -0.20 * buy_value, pnl_pct: -0.20, ltp: 80.0)
      snapshot = { pnl_pct: -0.20, pnl: -0.20 * buy_value, ltp: 80.0 }

      result = sl_tp_engine.evaluate(context_for(position, snapshot: snapshot))
      expect(result.exit?).to be true
      expect(result.reason).to include('STOP_LOSS')
    end

    it 'stops evaluation after first exit rule triggers' do
      position = build_position(pnl: 0.60 * buy_value, pnl_pct: 0.60, ltp: 160.0)
      snapshot = { pnl_pct: 0.60, pnl: 0.60 * buy_value, ltp: 160.0 }

      result = sl_tp_engine.evaluate(context_for(position, snapshot: snapshot))
      expect(result.exit?).to be true
      expect(result.reason).to include('TAKE_PROFIT')
    end
  end

  describe 'Full Lifecycle: Trailing Activation → Peak → Drawdown → Exit' do
    let(:trailing_engine) do
      Risk::Rules::RuleEngine.new(rules: [Risk::Rules::TrailingStopRule.new(config: risk_config)])
    end

    it 'simulates complete position lifecycle with trailing activation' do
      allow(Live::UnifiedExitChecker).to receive(:evaluate_underlying_context)
        .and_return(action: :none, multiplier: 1.0)
      allow(Live::UnifiedExitChecker).to receive(:trailing_stop_hit?).and_return(false, false, false, true)

      # Step 1: Position at 5% (below activation threshold)
      position1 = build_position(pnl: 0.05 * buy_value, pnl_pct: 0.05, ltp: 105.0, peak_profit_pct: 0.05)
      snapshot1 = { pnl_pct: 0.05, pnl: 0.05 * buy_value, ltp: 105.0, hwm_pnl: 0.05 * buy_value }
      result1 = trailing_engine.evaluate(context_for(position1, snapshot: snapshot1))
      expect(result1.no_action?).to be true # No exit, trailing not activated

      # Step 2: Position reaches 10% (activation threshold)
      position2 = build_position(pnl: 0.10 * buy_value, pnl_pct: 0.10, ltp: 110.0, peak_profit_pct: 0.10)
      snapshot2 = { pnl_pct: 0.10, pnl: 0.10 * buy_value, ltp: 110.0, hwm_pnl: 0.10 * buy_value }
      result2 = trailing_engine.evaluate(context_for(position2, snapshot: snapshot2))
      expect(result2.no_action?).to be true # No exit yet, trailing activated

      # Step 3: Position peaks at 25%
      position3 = build_position(pnl: 0.25 * buy_value, pnl_pct: 0.25, ltp: 125.0, peak_profit_pct: 0.25)
      snapshot3 = { pnl_pct: 0.25, pnl: 0.25 * buy_value, ltp: 125.0, hwm_pnl: 0.25 * buy_value }
      result3 = trailing_engine.evaluate(context_for(position3, snapshot: snapshot3))
      expect(result3.no_action?).to be true # No exit, at peak

      # Step 4: Position drops to 20% (5% drawdown from peak)
      position4 = build_position(pnl: 0.20 * buy_value, pnl_pct: 0.20, ltp: 120.0, peak_profit_pct: 0.25)
      snapshot4 = { pnl_pct: 0.20, pnl: 0.20 * buy_value, ltp: 120.0, hwm_pnl: 0.25 * buy_value }
      result4 = trailing_engine.evaluate(context_for(position4, snapshot: snapshot4))
      expect(result4.exit?).to be true # Exit triggered
      expect(result4.reason).to include('TRAILING_STOP')
    end
  end

  describe 'Edge Cases' do
    it 'handles zero PnL gracefully' do
      position = build_position(pnl: 0.0, pnl_pct: 0.0, ltp: 100.0)
      snapshot = { pnl_pct: 0.0, pnl: 0.0, ltp: 100.0 }

      result = rule_engine.evaluate(context_for(position, snapshot: snapshot))
      expect(result.exit?).to be false
    end

    it 'handles nil PnL percentage gracefully' do
      position = build_position(pnl: 0.0, pnl_pct: nil, ltp: 100.0)

      result = rule_engine.evaluate(context_for(position))
      expect(result.exit?).to be false
    end

    it 'handles exited position gracefully' do
      tracker.update(status: 'exited')
      position = build_position(pnl: 0.10 * buy_value, pnl_pct: 0.10, ltp: 110.0)
      snapshot = { pnl_pct: 0.10, pnl: 0.10 * buy_value, ltp: 110.0 }

      result = rule_engine.evaluate(context_for(position, snapshot: snapshot))
      expect(result.skip?).to be true
    end
  end
end
