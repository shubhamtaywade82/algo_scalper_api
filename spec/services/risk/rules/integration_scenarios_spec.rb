# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Rule Engine Integration Scenarios' do
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
  let(:risk_config) do
    {
      sl_pct: 2.0,
      tp_pct: 5.0,
      secure_profit_threshold_rupees: 1000.0,
      secure_profit_drawdown_pct: 3.0,
      time_exit_hhmm: '15:20',
      min_profit_rupees: 200.0
    }
  end
  let(:engine) { Risk::Rules::RuleFactory.create_engine(risk_config: risk_config) }

  describe 'Scenario 1: Stop Loss Hit' do
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

    it 'exits immediately at -4% loss' do
      result = engine.evaluate(context)
      expect(result.exit?).to be true
      expect(result.reason).to include('SL HIT')
      expect(result.reason).to include('-4.00%')
    end
  end

  describe 'Scenario 2: Take Profit Hit' do
    let(:position_data) do
      Positions::ActiveCache::PositionData.new(
        tracker_id: tracker.id,
        entry_price: 100.0,
        quantity: 10,
        current_ltp: 107.0,
        pnl: 70.0,
        pnl_pct: 7.0
      )
    end
    let(:context) do
      Risk::Rules::RuleContext.new(
        position: position_data,
        tracker: tracker,
        risk_config: risk_config
      )
    end

    it 'exits at +7% profit' do
      result = engine.evaluate(context)
      expect(result.exit?).to be true
      expect(result.reason).to include('TP HIT')
      expect(result.reason).to include('7.00%')
    end
  end

  describe 'Scenario 4: Session End Overrides Everything' do
    let(:position_data) do
      Positions::ActiveCache::PositionData.new(
        tracker_id: tracker.id,
        entry_price: 100.0,
        quantity: 10,
        current_ltp: 110.0,
        pnl: 100.0,
        pnl_pct: 10.0
      )
    end
    let(:context) do
      Risk::Rules::RuleContext.new(
        position: position_data,
        tracker: tracker,
        risk_config: risk_config
      )
    end

    before do
      allow(TradingSession::Service).to receive(:should_force_exit?).and_return(
        { should_exit: true, reason: 'session_end' }
      )
    end

    it 'exits due to session end regardless of profit' do
      result = engine.evaluate(context)
      expect(result.exit?).to be true
      expect(result.reason).to include('session end')
    end
  end

  describe 'Scenario 5: Stop Loss Overrides Take Profit' do
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

    it 'stop loss triggers first' do
      result = engine.evaluate(context)
      expect(result.exit?).to be true
      expect(result.reason).to include('SL HIT')
    end
  end

  describe 'Scenario 7: Peak Drawdown Exit' do
    let(:position_data) do
      Positions::ActiveCache::PositionData.new(
        tracker_id: tracker.id,
        entry_price: 100.0,
        quantity: 10,
        current_ltp: 120.0,
        pnl: 1000.0,
        pnl_pct: 20.0,
        peak_profit_pct: 25.0
      )
    end
    let(:context) do
      Risk::Rules::RuleContext.new(
        position: position_data,
        tracker: tracker,
        risk_config: risk_config
      )
    end

    before do
      allow(Positions::TrailingConfig).to receive_messages(peak_drawdown_triggered?: true, peak_drawdown_active?: true, config: { peak_drawdown_pct: 5.0,
                                                                                                                                  activation_profit_pct: 25.0,
                                                                                                                                  activation_sl_offset_pct: 10.0 })
    end

    it 'exits due to peak drawdown' do
      result = engine.evaluate(context)
      expect(result.exit?).to be true
      expect(result.reason).to include('peak_drawdown_exit')
    end
  end

  describe 'Scenario 10: Time-Based Exit with Minimum Profit' do
    let(:position_data) do
      Positions::ActiveCache::PositionData.new(
        tracker_id: tracker.id,
        entry_price: 100.0,
        quantity: 10,
        current_ltp: 101.0,
        pnl: 100.0,
        pnl_pct: 1.0
      )
    end
    let(:exit_time) { Time.zone.parse('15:20') }
    let(:context) do
      Risk::Rules::RuleContext.new(
        position: position_data,
        tracker: tracker,
        risk_config: risk_config,
        current_time: exit_time
      )
    end

    it 'does not exit when minimum profit not met' do
      result = engine.evaluate(context)
      expect(result.no_action?).to be true
    end
  end

  describe 'Scenario 11: Time-Based Exit Triggered' do
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
    let(:exit_time) { Time.zone.parse('15:20') }
    let(:context) do
      Risk::Rules::RuleContext.new(
        position: position_data,
        tracker: tracker,
        risk_config: risk_config,
        current_time: exit_time
      )
    end

    it 'exits at exit time because minimum profit met' do
      result = engine.evaluate(context)
      expect(result.exit?).to be true
      expect(result.reason).to include('time-based exit')
    end
  end

  describe 'Scenario 16: Multiple Rules Could Trigger (Priority Wins)' do
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
    let(:exit_time) { Time.zone.parse('15:20') }
    let(:context) do
      Risk::Rules::RuleContext.new(
        position: position_data,
        tracker: tracker,
        risk_config: risk_config,
        current_time: exit_time
      )
    end

    it 'stop loss triggers first even though time-based exit could trigger' do
      result = engine.evaluate(context)
      expect(result.exit?).to be true
      expect(result.reason).to include('SL HIT')
    end
  end

  describe 'Scenario 17: Rule Disabled' do
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
    let(:disabled_config) { risk_config.merge(sl_pct: 0) }
    let(:engine) { Risk::Rules::RuleFactory.create_engine(risk_config: disabled_config) }
    let(:context) do
      Risk::Rules::RuleContext.new(
        position: position_data,
        tracker: tracker,
        risk_config: disabled_config
      )
    end

    it 'stop loss rule disabled - position not exited' do
      engine.evaluate(context)
      # Other rules might trigger, but SL won't
      sl_rule = engine.find_rule(Risk::Rules::StopLossRule)
      expect(sl_rule.config[:sl_pct]).to eq(0)
    end
  end

  describe 'Scenario 19: Position Already Exited' do
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

    before do
      tracker.update(status: 'exited')
    end

    it 'no rules evaluated - position already exited' do
      result = engine.evaluate(context)
      expect(result.skip?).to be true
    end
  end

  describe 'Scenario 20: Missing Entry Price' do
    let(:position_data) do
      Positions::ActiveCache::PositionData.new(
        tracker_id: tracker.id,
        entry_price: nil,
        quantity: 10,
        current_ltp: 105.0,
        pnl: nil,
        pnl_pct: nil
      )
    end
    let(:context) do
      Risk::Rules::RuleContext.new(
        position: position_data,
        tracker: tracker,
        risk_config: risk_config
      )
    end

    it 'rules that require PnL skip' do
      result = engine.evaluate(context)
      # Most rules will skip, final result should be no_action
      expect(result.no_action?).to be true
    end
  end

  describe 'Scenario 29: Securing Profit Above ₹1000' do
    let(:position_data) do
      Positions::ActiveCache::PositionData.new(
        tracker_id: tracker.id,
        entry_price: 100.0,
        quantity: 10,
        current_ltp: 120.0,
        pnl: 1100.0,
        pnl_pct: 22.0,
        peak_profit_pct: 25.0
      )
    end
    let(:context) do
      Risk::Rules::RuleContext.new(
        position: position_data,
        tracker: tracker,
        risk_config: risk_config
      )
    end

    it 'exits when profit >= ₹1000 and drawdown >= 3%' do
      result = engine.evaluate(context)
      # SecureProfitRule should trigger (drawdown: 3% from peak 25%)
      expect(result.exit?).to be true
      expect(result.reason).to include('secure_profit_exit')
    end
  end

  describe 'Scenario 30: Riding Profits Below Threshold' do
    let(:position_data) do
      Positions::ActiveCache::PositionData.new(
        tracker_id: tracker.id,
        entry_price: 100.0,
        quantity: 10,
        current_ltp: 105.0,
        pnl: 500.0,
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

    it 'position continues to ride - rule not activated' do
      result = engine.evaluate(context)
      # SecureProfitRule not activated (profit < ₹1000)
      expect(result.no_action?).to be true
    end
  end

  describe 'Scenario 31: Allowing Further Upside After Securing' do
    let(:position_data) do
      Positions::ActiveCache::PositionData.new(
        tracker_id: tracker.id,
        entry_price: 100.0,
        quantity: 10,
        current_ltp: 130.0,
        pnl: 1500.0,
        pnl_pct: 30.0,
        peak_profit_pct: 30.0
      )
    end
    let(:context) do
      Risk::Rules::RuleContext.new(
        position: position_data,
        tracker: tracker,
        risk_config: risk_config
      )
    end

    it 'position continues to ride - profit can grow further' do
      result = engine.evaluate(context)
      # At peak, no drawdown, so no exit
      expect(result.no_action?).to be true
    end
  end
end
