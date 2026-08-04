# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Risk Rule Engine - Full Position Simulation (Integration)', type: :service do
  # Test configuration
  let(:lot_size) { 75 }
  let(:lots) { 4 }
  let(:qty) { lot_size * lots } # 300 units
  let(:entry_premium) { BigDecimal('100.0') }
  let(:buy_value) { (entry_premium * qty).to_f } # 100 * 300 = 30,000

  # Risk configuration for tests (decimals: 0.20 = 20%)
  let(:risk_config) do
    {
      sl_pct: 0.20,
      tp_pct: 0.60,
      trailing: {
        activation_pct: 0.10,
        drawdown_pct: 0.03
      },
      secure_profit_threshold_rupees: 1000.0,
      secure_profit_drawdown_pct: 0.03,
      peak_drawdown_exit_pct: 0.05,
      time_exit_hhmm: '15:20',
      min_profit_rupees: 200.0,
      underlying_trend_score_threshold: 10.0,
      underlying_atr_collapse_multiplier: 0.65
    }
  end

  # Create test doubles for external dependencies
  let(:exit_engine) { double('ExitEngine', exit: true) }
  let(:redis_pnl_cache) { instance_double(Live::RedisPnlCache) }
  let(:active_cache) { Positions::ActiveCache.instance }

  # Real components
  let(:rule_engine) { Risk::Rules::RuleFactory.create_engine(risk_config: risk_config) }

  # Test position setup
  let(:instrument) { create(:instrument, :nifty_future) }
  let(:tracker) do
    create(
      :position_tracker,
      instrument: instrument,
      status: 'active',
      entry_price: entry_premium.to_f,
      quantity: qty,
      segment: 'NSE_FNO',
      security_id: instrument.security_id
    )
  end

  # Helper to create/update position in ActiveCache
  def create_position_in_cache(pnl:, pnl_pct:, ltp:, hwm_pnl: nil, peak_profit_pct: nil)
    position_data = active_cache.add_position(tracker: tracker)
    raise 'ActiveCache#add_position returned nil' unless position_data

    position_data.current_ltp = ltp
    position_data.pnl = pnl
    position_data.pnl_pct = pnl_pct
    position_data.high_water_mark = hwm_pnl || pnl
    position_data.peak_profit_pct = peak_profit_pct || pnl_pct
    position_data.last_updated_at = Time.current
    position_data
  end

  # Helper to mock Redis PnL cache response
  def mock_redis_pnl(pnl:, pnl_pct:, ltp:, hwm_pnl: nil, timestamp: Time.current.to_i)
    allow(Live::RedisPnlCache.instance).to receive(:fetch_pnl).with(tracker.id).and_return(
      {
        pnl: pnl.to_f,
        pnl_pct: pnl_pct.to_f,
        ltp: ltp.to_f,
        hwm_pnl: (hwm_pnl || pnl).to_f,
        timestamp: timestamp
      }
    )
  end

  # Helper to process position through the rule engine (same exit outcome as risk path)
  def process_position(position_data)
    allow(Live::RedisPnlCache.instance).to receive(:fetch_pnl).and_return(nil)

    context = Risk::Rules::RuleContext.new(
      position: position_data,
      tracker: tracker,
      risk_config: risk_config,
      current_time: Time.zone.parse('2024-01-01 10:00:00 IST')
    )
    decision = rule_engine.evaluate(context)
    return false unless decision.exit?

    exit_engine.exit(tracker, reason: decision.reason)
    true
  end

  before do
    # Clear ActiveCache before each test
    active_cache.clear

    # Mock AlgoConfig to return our test risk_config
    allow(AlgoConfig).to receive(:fetch).and_return(risk: risk_config)

    # Mock TradingSession
    allow(TradingSession::Service).to receive_messages(
      market_closed?: false,
      session_ending?: false,
      should_force_exit?: { should_exit: false }
    )

    # Mock Positions::TrailingConfig for peak drawdown
    allow(Positions::TrailingConfig).to receive_messages(peak_drawdown_triggered?: false, peak_drawdown_active?: true, config: { peak_drawdown_pct: 0.05,
                                                                                                                                 activation_profit_pct: 0.25,
                                                                                                                                 activation_sl_offset_pct: 0.10 })

    # Mock UnderlyingMonitor for underlying exit tests
    allow(Live::UnderlyingMonitor).to receive(:evaluate).and_return(nil)
  end

  describe 'Stop Loss Exit' do
    it 'exits when PnL drops to -20% (stop loss threshold)' do
      position = create_position_in_cache(
        pnl: -0.20 * buy_value, # -₹6,000
        pnl_pct: -0.2,
        ltp: 80.0
      )

      expect(exit_engine).to receive(:exit).with(
        tracker,
        hash_including(reason: match(/stop.*loss/i))
      )

      result = process_position(position)
      expect(result).to be true # Exit was triggered
    end

    it 'does not exit when loss is less than stop loss threshold' do
      position = create_position_in_cache(
        pnl: -0.10 * buy_value, # -₹3,000 (-10%)
        pnl_pct: -0.1,
        ltp: 90.0
      )

      expect(exit_engine).not_to receive(:exit)
      result = process_position(position)
      expect(result).to be false # No exit
    end
  end

  describe 'Take Profit Exit' do
    it 'exits when PnL reaches +60% (take profit threshold)' do
      position = create_position_in_cache(
        pnl: 0.60 * buy_value, # +₹18,000
        pnl_pct: 0.6,
        ltp: 160.0
      )

      expect(exit_engine).to receive(:exit).with(
        tracker,
        hash_including(reason: match(/take.*profit/i))
      )

      result = process_position(position)
      expect(result).to be true
    end

    it 'does not exit when profit is below take profit threshold' do
      position = create_position_in_cache(
        pnl: 0.30 * buy_value, # +₹9,000 (+30%)
        pnl_pct: 0.3,
        ltp: 130.0
      )

      expect(exit_engine).not_to receive(:exit)
      result = process_position(position)
      expect(result).to be false
    end
  end

  describe 'Trailing Activation Threshold' do
    it 'does not activate trailing rules when pnl_pct < 10%' do
      position = create_position_in_cache(
        pnl: 0.05 * buy_value, # +₹1,500 (+5%)
        pnl_pct: 0.05,
        ltp: 105.0,
        hwm_pnl: 0.05 * buy_value,
        peak_profit_pct: 5.0
      )

      # PeakDrawdownRule should skip (not activated)
      peak_rule = rule_engine.find_rule(Risk::Rules::PeakDrawdownRule)
      context = Risk::Rules::RuleContext.new(
        position: position,
        tracker: tracker,
        risk_config: risk_config,
        current_time: Time.current,
        trading_session: TradingSession::Service
      )
      result = peak_rule.evaluate(context)
      expect(result.skip?).to be true
    end

    it 'activates trailing rules when pnl_pct >= 10%' do
      position = create_position_in_cache(
        pnl: 0.10 * buy_value, # +₹3,000 (+10%)
        pnl_pct: 0.1,
        ltp: 110.0,
        hwm_pnl: 0.10 * buy_value,
        peak_profit_pct: 10.0
      )

      # PeakDrawdownRule should evaluate (not skip)
      peak_rule = rule_engine.find_rule(Risk::Rules::PeakDrawdownRule)
      context = Risk::Rules::RuleContext.new(
        position: position,
        tracker: tracker,
        risk_config: risk_config,
        current_time: Time.current,
        trading_session: TradingSession::Service
      )
      result = peak_rule.evaluate(context)
      # May return no_action if drawdown not triggered, but should not skip
      expect(result.skip?).to be false
    end

    it 'works with custom activation threshold (6%)' do
      custom_config = risk_config.dup
      custom_config[:trailing][:activation_pct] = 6.0

      custom_engine = Risk::Rules::RuleFactory.create_engine(risk_config: custom_config)

      # At 6% - should activate
      position = create_position_in_cache(
        pnl: 0.06 * buy_value,
        pnl_pct: 0.06,
        ltp: 106.0
      )

      peak_rule = custom_engine.find_rule(Risk::Rules::PeakDrawdownRule)
      context = Risk::Rules::RuleContext.new(
        position: position,
        tracker: tracker,
        risk_config: custom_config,
        current_time: Time.current,
        trading_session: TradingSession::Service
      )
      result = peak_rule.evaluate(context)
      expect(result.skip?).to be false

      # At 5.99% - should skip
      position.pnl_pct = 5.99
      result = peak_rule.evaluate(context)
      expect(result.skip?).to be true
    end
  end

  describe 'Secure Profit Rule' do
    it 'exits when profit >= ₹1000 and drawdown >= 3% from peak' do
      # Peak at +25%, current at +21% (4% drawdown from peak)
      position = create_position_in_cache(
        pnl: 0.21 * buy_value, # +₹6,300 (> ₹1000 threshold)
        pnl_pct: 0.21,
        ltp: 121.0,
        peak_profit_pct: 25.0 # Peak was 25%
      )

      expect(exit_engine).to receive(:exit).with(
        tracker,
        hash_including(reason: match(/secure.*profit/i))
      )

      result = process_position(position)
      expect(result).to be true
    end

    it 'does not exit when profit < ₹1000 even with drawdown' do
      position = create_position_in_cache(
        pnl: 0.02 * buy_value, # +₹600 (< ₹1000 threshold)
        pnl_pct: 0.02,
        ltp: 102.0,
        peak_profit_pct: 5.0
      )

      expect(exit_engine).not_to receive(:exit)
      result = process_position(position)
      expect(result).to be false
    end

    it 'allows position to ride when profit >= ₹1000 but no drawdown yet' do
      position = create_position_in_cache(
        pnl: 0.15 * buy_value, # +₹4,500 (> ₹1000)
        pnl_pct: 0.15,
        ltp: 115.0,
        peak_profit_pct: 15.0 # At peak, no drawdown
      )

      expect(exit_engine).not_to receive(:exit)
      result = process_position(position)
      expect(result).to be false
    end
  end

  describe 'Peak Drawdown Exit' do
    before do
      allow(Positions::TrailingConfig).to receive(:peak_drawdown_triggered?).and_return(true)
    end

    it 'exits when drawdown >= 5% from peak after trailing activation' do
      # Peak at +25%, current at +19% (6% drawdown)
      position = create_position_in_cache(
        pnl: 0.19 * buy_value,
        pnl_pct: 0.19,
        ltp: 119.0,
        peak_profit_pct: 25.0
      )

      expect(exit_engine).to receive(:exit).with(
        tracker,
        hash_including(reason: match(/peak.*drawdown/i))
      )

      result = process_position(position)
      expect(result).to be true
    end

    it 'does not exit when drawdown < 5% from peak' do
      position = create_position_in_cache(
        pnl: 0.22 * buy_value, # +22% (3% drawdown from 25% peak)
        pnl_pct: 0.22,
        ltp: 122.0,
        peak_profit_pct: 25.0
      )

      allow(Positions::TrailingConfig).to receive(:peak_drawdown_triggered?).and_return(false)
      expect(exit_engine).not_to receive(:exit)
      result = process_position(position)
      expect(result).to be false
    end
  end

  describe 'Time-Based Exit' do
    it 'exits at configured time (15:20) when minimum profit met' do
      allow(Time).to receive(:current).and_return(Time.zone.parse('2024-01-01 15:20:00'))
      allow(TradingSession::Service).to receive(:market_closed?).and_return(false)

      position = create_position_in_cache(
        pnl: 0.10 * buy_value, # +₹3,000 (> ₹200 min)
        pnl_pct: 0.1,
        ltp: 110.0
      )

      expect(exit_engine).to receive(:exit).with(
        tracker,
        hash_including(reason: match(/time.*based/i))
      )

      result = process_position(position)
      expect(result).to be true
    end

    it 'does not exit when minimum profit not met' do
      allow(Time).to receive(:current).and_return(Time.zone.parse('2024-01-01 15:20:00'))

      position = create_position_in_cache(
        pnl: 0.005 * buy_value, # +₹150 (< ₹200 min)
        pnl_pct: 0.005,
        ltp: 100.5
      )

      expect(exit_engine).not_to receive(:exit)
      result = process_position(position)
      expect(result).to be false
    end

    it 'does not exit before configured time' do
      allow(Time).to receive(:current).and_return(Time.zone.parse('2024-01-01 15:19:00'))

      position = create_position_in_cache(
        pnl: 0.10 * buy_value,
        pnl_pct: 0.1,
        ltp: 110.0
      )

      expect(exit_engine).not_to receive(:exit)
      result = process_position(position)
      expect(result).to be false
    end
  end

  describe 'Session End Exit' do
    it 'exits at session end (3:15 PM)' do
      allow(TradingSession::Service).to receive(:session_ending?).and_return(true)

      position = create_position_in_cache(
        pnl: 0.05 * buy_value,
        pnl_pct: 0.05,
        ltp: 105.0
      )

      expect(exit_engine).to receive(:exit).with(
        tracker,
        hash_including(reason: match(/session.*end/i))
      )

      result = process_position(position)
      expect(result).to be true
    end
  end

  describe 'Underlying Structure Break' do
    it 'exits when underlying structure breaks' do
      skip 'Covered by UnderlyingExitRule specs; RiskManager private helpers removed'
    end
  end

  describe 'Stale Data Handling' do
    it 'skips evaluation when Redis data is stale (>30 seconds)' do
      skip 'Redis sync path lives in RiskManager PnL pipeline; exercise via integration tests'
    end

    it 'uses fresh Redis data when timestamp is recent (<30 seconds)' do
      skip 'Redis sync path lives in RiskManager PnL pipeline; exercise via integration tests'
    end
  end

  describe 'Missing Entry Price' do
    it 'skips evaluation when entry price is missing' do
      bad_tracker = create(
        :position_tracker,
        instrument: instrument,
        status: 'active',
        entry_price: nil, # Missing entry price
        quantity: qty
      )

      position = Positions::PositionData.new(
        tracker_id: bad_tracker.id,
        entry_price: nil,
        quantity: qty,
        current_ltp: 100.0,
        pnl: 0.0,
        pnl_pct: 0.0
      )

      context = Risk::Rules::RuleContext.new(
        position: position,
        tracker: bad_tracker,
        risk_config: risk_config,
        current_time: Time.current,
        trading_session: TradingSession::Service
      )

      result = rule_engine.evaluate(context)
      expect(result.skip?).to be true
    end
  end

  describe 'Disabled Rules' do
    it 'skips evaluation when rule is disabled via config' do
      disabled_config = risk_config.dup
      disabled_config[:sl_pct] = 0 # Disable stop loss

      disabled_engine = Risk::Rules::RuleFactory.create_engine(risk_config: disabled_config)
      sl_rule = disabled_engine.find_rule(Risk::Rules::StopLossRule)

      # Disable the rule
      allow(sl_rule).to receive(:enabled?).and_return(false)

      position = create_position_in_cache(
        pnl: -0.25 * buy_value, # -25% (would trigger SL if enabled)
        pnl_pct: -0.25,
        ltp: 75.0
      )

      context = Risk::Rules::RuleContext.new(
        position: position,
        tracker: tracker,
        risk_config: disabled_config,
        current_time: Time.current,
        trading_session: TradingSession::Service
      )

      result = disabled_engine.evaluate(context)
      # Should not exit (SL disabled), may return no_action from other rules
      expect(result.exit?).to be false
    end
  end

  describe 'Priority Order' do
    it 'evaluates rules in priority order (SL before TP)' do
      # Position that would trigger both SL and TP (impossible, but tests priority)
      # In reality, SL would trigger first
      position = create_position_in_cache(
        pnl: -0.20 * buy_value, # -20% (SL threshold)
        pnl_pct: -0.2,
        ltp: 80.0
      )

      # SL rule (priority 20) should trigger before TP rule (priority 30)
      expect(exit_engine).to receive(:exit).with(
        tracker,
        hash_including(reason: match(/stop.*loss/i))
      )

      result = process_position(position)
      expect(result).to be true
    end

    it 'stops evaluation after first exit rule triggers' do
      position = create_position_in_cache(
        pnl: 0.60 * buy_value, # +60% (TP threshold)
        pnl_pct: 0.6,
        ltp: 160.0
      )

      # TP rule (priority 30) should trigger, SecureProfitRule (priority 35) should not be evaluated
      expect(exit_engine).to receive(:exit).once
      result = process_position(position)
      expect(result).to be true
    end
  end

  describe 'Full Lifecycle: Trailing Activation → Peak → Drawdown → Exit' do
    it 'simulates complete position lifecycle with trailing activation' do
      # Step 1: Position at 5% (below activation threshold)
      position1 = create_position_in_cache(
        pnl: 0.05 * buy_value,
        pnl_pct: 0.05,
        ltp: 105.0,
        peak_profit_pct: 5.0
      )
      result1 = process_position(position1)
      expect(result1).to be false # No exit, trailing not activated

      # Step 2: Position reaches 10% (activation threshold)
      position2 = create_position_in_cache(
        pnl: 0.10 * buy_value,
        pnl_pct: 0.1,
        ltp: 110.0,
        peak_profit_pct: 10.0
      )
      result2 = process_position(position2)
      expect(result2).to be false # No exit yet, trailing activated

      # Step 3: Position peaks at 25%
      position3 = create_position_in_cache(
        pnl: 0.25 * buy_value,
        pnl_pct: 0.25,
        ltp: 125.0,
        peak_profit_pct: 25.0
      )
      result3 = process_position(position3)
      expect(result3).to be false # No exit, at peak

      # Step 4: Position drops to 20% (5% drawdown from peak)
      allow(Positions::TrailingConfig).to receive(:peak_drawdown_triggered?).and_return(true)
      position4 = create_position_in_cache(
        pnl: 0.20 * buy_value,
        pnl_pct: 0.2,
        ltp: 120.0,
        peak_profit_pct: 25.0
      )

      expect(exit_engine).to receive(:exit).with(
        tracker,
        hash_including(reason: match(/peak.*drawdown/i))
      )
      result4 = process_position(position4)
      expect(result4).to be true # Exit triggered
    end
  end

  describe 'Edge Cases' do
    it 'handles zero PnL gracefully' do
      position = create_position_in_cache(
        pnl: 0.0,
        pnl_pct: 0.0,
        ltp: 100.0
      )

      expect(exit_engine).not_to receive(:exit)
      result = process_position(position)
      expect(result).to be false
    end

    it 'handles nil PnL percentage gracefully' do
      position = create_position_in_cache(
        pnl: 0.0,
        pnl_pct: nil,
        ltp: 100.0
      )

      # Rules should skip when pnl_pct is nil
      context = Risk::Rules::RuleContext.new(
        position: position,
        tracker: tracker,
        risk_config: risk_config,
        current_time: Time.current,
        trading_session: TradingSession::Service
      )
      result = rule_engine.evaluate(context)
      expect(result.skip?).to be true
    end

    it 'handles exited position gracefully' do
      tracker.update(status: 'exited')
      position = create_position_in_cache(
        pnl: 0.10 * buy_value,
        pnl_pct: 0.1,
        ltp: 110.0
      )

      context = Risk::Rules::RuleContext.new(
        position: position,
        tracker: tracker,
        risk_config: risk_config,
        current_time: Time.current,
        trading_session: TradingSession::Service
      )
      result = rule_engine.evaluate(context)
      expect(result.skip?).to be true
    end
  end
end
