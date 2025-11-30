# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Risk::Rules::RuleContext do
  let(:instrument) { create(:instrument, :nifty_future, security_id: '9999') }
  let(:tracker) do
    create(
      :position_tracker,
      instrument: instrument,
      order_no: 'ORD123456',
      security_id: '50074',
      segment: 'NSE_FNO',
      status: 'active',
      quantity: 75,
      entry_price: 100.0,
      avg_price: 100.0
    )
  end
  let(:position_data) do
    Positions::ActiveCache::PositionData.new(
      tracker_id: tracker.id,
      security_id: '50074',
      segment: 'NSE_FNO',
      entry_price: 100.0,
      quantity: 75,
      current_ltp: 105.0,
      pnl: 375.0,
      pnl_pct: 5.0,
      peak_profit_pct: 7.0,
      high_water_mark: 525.0
    )
  end
  let(:risk_config) do
    {
      sl_pct: 2.0,
      tp_pct: 5.0,
      secure_profit_threshold_rupees: 1000.0
    }
  end
  let(:context) do
    described_class.new(
      position: position_data,
      tracker: tracker,
      risk_config: risk_config,
      current_time: Time.current,
      trading_session: TradingSession::Service
    )
  end

  describe '#initialize' do
    it 'sets all attributes correctly' do
      expect(context.position).to eq(position_data)
      expect(context.tracker).to eq(tracker)
      expect(context.risk_config).to eq(risk_config)
      expect(context.current_time).to be_a(Time)
      expect(context.trading_session).to eq(TradingSession::Service)
    end
  end

  describe '#pnl_pct' do
    it 'returns PnL percentage from position' do
      expect(context.pnl_pct).to eq(5.0)
    end

    it 'returns nil when position has no PnL percentage' do
      position_data.pnl_pct = nil
      expect(context.pnl_pct).to be_nil
    end
  end

  describe '#pnl_rupees' do
    it 'returns PnL in rupees from position' do
      expect(context.pnl_rupees).to eq(375.0)
    end

    it 'returns nil when position has no PnL' do
      position_data.pnl = nil
      expect(context.pnl_rupees).to be_nil
    end
  end

  describe '#peak_profit_pct' do
    it 'returns peak profit percentage from position' do
      expect(context.peak_profit_pct).to eq(7.0)
    end

    it 'returns nil when position has no peak profit' do
      position_data.peak_profit_pct = nil
      expect(context.peak_profit_pct).to be_nil
    end
  end

  describe '#high_water_mark' do
    it 'returns high water mark from position' do
      expect(context.high_water_mark).to eq(525.0)
    end
  end

  describe '#current_ltp' do
    it 'returns current LTP from position' do
      expect(context.current_ltp).to eq(105.0)
    end
  end

  describe '#entry_price' do
    it 'returns entry price from tracker' do
      expect(context.entry_price).to eq(100.0)
    end
  end

  describe '#quantity' do
    it 'returns quantity from tracker' do
      expect(context.quantity).to eq(75)
    end
  end

  describe '#active?' do
    it 'returns true when tracker is active and position exists' do
      expect(context.active?).to be true
    end

    it 'returns false when tracker is exited' do
      tracker.update(status: 'exited')
      expect(context.active?).to be false
    end

    it 'returns false when position is nil' do
      context = described_class.new(
        position: nil,
        tracker: tracker,
        risk_config: risk_config
      )
      expect(context.active?).to be false
    end
  end

  describe '#config_value' do
    it 'returns config value by symbol key' do
      expect(context.config_value(:sl_pct)).to eq(2.0)
    end

    it 'returns config value by string key' do
      expect(context.config_value('sl_pct')).to eq(2.0)
    end

    it 'returns default when key not found' do
      expect(context.config_value(:nonexistent, 'default')).to eq('default')
    end
  end

  describe '#config_bigdecimal' do
    it 'returns BigDecimal value from config' do
      result = context.config_bigdecimal(:sl_pct, BigDecimal('0'))
      expect(result).to eq(BigDecimal('2.0'))
    end

    it 'returns default when key not found' do
      result = context.config_bigdecimal(:nonexistent, BigDecimal('5.0'))
      expect(result).to eq(BigDecimal('5.0'))
    end

    it 'handles string values' do
      risk_config[:sl_pct] = '2.5'
      result = context.config_bigdecimal(:sl_pct, BigDecimal('0'))
      expect(result).to eq(BigDecimal('2.5'))
    end

    it 'returns default on error' do
      risk_config[:sl_pct] = 'invalid'
      result = context.config_bigdecimal(:sl_pct, BigDecimal('5.0'))
      expect(result).to eq(BigDecimal('5.0'))
    end
  end

  describe '#config_time' do
    it 'parses time from HH:MM format' do
      risk_config[:time_exit_hhmm] = '15:20'
      result = context.config_time(:time_exit_hhmm)
      expect(result).to be_a(Time)
      expect(result.hour).to eq(15)
      expect(result.min).to eq(20)
    end

    it 'returns default when key not found' do
      result = context.config_time(:nonexistent, Time.zone.parse('10:00'))
      expect(result).to eq(Time.zone.parse('10:00'))
    end

    it 'returns default on parse error' do
      risk_config[:time_exit_hhmm] = 'invalid'
      result = context.config_time(:time_exit_hhmm, Time.zone.parse('10:00'))
      expect(result).to eq(Time.zone.parse('10:00'))
    end
  end

  describe '#trailing_activation_pct' do
    context 'with nested config' do
      before do
        risk_config[:trailing] = { activation_pct: 10.0 }
      end

      it 'returns value from nested config' do
        expect(context.trailing_activation_pct).to eq(BigDecimal('10.0'))
      end
    end

    context 'with flat config' do
      before do
        risk_config[:trailing_activation_pct] = 6.66
      end

      it 'returns value from flat config' do
        expect(context.trailing_activation_pct).to eq(BigDecimal('6.66'))
      end
    end

    context 'with default' do
      it 'returns default 10.0' do
        expect(context.trailing_activation_pct).to eq(BigDecimal('10.0'))
      end
    end
  end

  describe '#trailing_activated?' do
    context 'when pnl_pct >= activation_pct' do
      before do
        position_data.pnl_pct = 10.0
        risk_config[:trailing] = { activation_pct: 10.0 }
      end

      it 'returns true' do
        expect(context.trailing_activated?).to be true
      end
    end

    context 'when pnl_pct < activation_pct' do
      before do
        position_data.pnl_pct = 5.0
        risk_config[:trailing] = { activation_pct: 10.0 }
      end

      it 'returns false' do
        expect(context.trailing_activated?).to be false
      end
    end

    context 'when pnl_pct is nil' do
      before do
        position_data.pnl_pct = nil
      end

      it 'returns false' do
        expect(context.trailing_activated?).to be false
      end
    end
  end
end
