# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Rule Engine Data Freshness' do
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

  describe 'live data from ActiveCache' do
    let(:position_data) do
      Positions::ActiveCache::PositionData.new(
        tracker_id: tracker.id,
        entry_price: 100.0,
        quantity: 10,
        current_ltp: 96.0,
        pnl: -40.0,
        pnl_pct: -4.0,
        last_updated_at: Time.current
      )
    end
    let(:context) do
      Risk::Rules::RuleContext.new(
        position: position_data,
        tracker: tracker,
        risk_config: risk_config
      )
    end

    it 'uses live data from ActiveCache for rule evaluation' do
      result = engine.evaluate(context)
      expect(result.exit?).to be true
      expect(result.reason).to include('SL HIT')
    end

    it 'uses current LTP from position data' do
      position_data.update_ltp(94.0)
      position_data.recalculate_pnl
      result = engine.evaluate(context)
      expect(result.exit?).to be true
    end
  end

  describe 'PnL recalculation' do
    let(:position_data) do
      Positions::ActiveCache::PositionData.new(
        tracker_id: tracker.id,
        entry_price: 100.0,
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

    it 'recalculates PnL when LTP is updated' do
      position_data.update_ltp(105.0)
      expect(position_data.pnl).to eq(50.0)
      expect(position_data.pnl_pct).to be_within(0.01).of(5.0)
    end
  end

  describe 'peak profit tracking' do
    let(:position_data) do
      Positions::ActiveCache::PositionData.new(
        tracker_id: tracker.id,
        entry_price: 100.0,
        quantity: 10,
        current_ltp: 120.0,
        pnl: 200.0,
        pnl_pct: 20.0,
        peak_profit_pct: nil
      )
    end

    it 'updates peak profit when PnL increases' do
      position_data.update_ltp(120.0)
      expect(position_data.peak_profit_pct).to eq(20.0)

      position_data.update_ltp(125.0)
      expect(position_data.peak_profit_pct).to eq(25.0)
    end

    it 'maintains peak profit when PnL decreases' do
      position_data.update_ltp(125.0)
      peak = position_data.peak_profit_pct

      position_data.update_ltp(120.0)
      expect(position_data.peak_profit_pct).to eq(peak)
    end
  end

  describe 'high water mark tracking' do
    let(:position_data) do
      Positions::ActiveCache::PositionData.new(
        tracker_id: tracker.id,
        entry_price: 100.0,
        quantity: 10,
        current_ltp: 110.0,
        pnl: 100.0,
        pnl_pct: 10.0,
        high_water_mark: nil
      )
    end

    it 'updates HWM when PnL increases' do
      position_data.update_ltp(110.0)
      expect(position_data.high_water_mark).to eq(100.0)

      position_data.update_ltp(120.0)
      expect(position_data.high_water_mark).to eq(200.0)
    end

    it 'maintains HWM when PnL decreases' do
      position_data.update_ltp(120.0)
      hwm = position_data.high_water_mark

      position_data.update_ltp(110.0)
      expect(position_data.high_water_mark).to eq(hwm)
    end
  end

  describe 'missing data handling' do
    let(:position_data) do
      Positions::ActiveCache::PositionData.new(
        tracker_id: tracker.id,
        entry_price: 100.0,
        quantity: 10,
        current_ltp: nil,
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

    it 'rules skip when required data is missing' do
      result = engine.evaluate(context)
      # Rules that require PnL will skip
      expect(result.no_action?).to be true
    end
  end

  describe 'data consistency' do
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

    it 'ensures PnL and PnL% are consistent' do
      # PnL should be (105 - 100) * 10 = 50
      # PnL% should be (105 - 100) / 100 * 100 = 5%
      expect(position_data.pnl).to eq(50.0)
      expect(position_data.pnl_pct).to be_within(0.01).of(5.0)
    end

    it 'recalculates PnL when LTP changes' do
      position_data.update_ltp(107.0)
      expect(position_data.pnl).to eq(70.0)
      expect(position_data.pnl_pct).to be_within(0.01).of(7.0)
    end
  end
end
