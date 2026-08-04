# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "Entries::EntryGuard Integration" do
  let(:index_cfg) { { key: 'NIFTY', segment: 'NSE_FNO', cooldown_sec: 60 } }
  let(:instrument) { create(:instrument, symbol_name: 'NIFTY', exchange: :nse, segment: :index) }
  let(:derivative) { create(:derivative, instrument: instrument, security_id: '12345', segment: :derivatives, expiry_flag: 'WEEKLY') }
  let(:pick) { { symbol: derivative.symbol_name, security_id: derivative.security_id, segment: 'NSE_FNO', derivative_id: derivative.id } }

  before do
    allow(AlgoConfig).to receive(:fetch).and_return({
      risk: {
        sl_pct: 0.12,
        time_regimes: { enabled: true }
      }
    })
    # Reset cache to ensure isolation
    Rails.cache.clear
  end

  describe '.weekly_contract?' do
    it 'returns true for weekly derivatives' do
      expect(Entries::EntryGuard.weekly_contract?(pick: pick, index_cfg: index_cfg)).to be true
    end

    it 'returns false for monthly derivatives' do
      derivative.update(expiry_flag: 'MONTHLY')
      expect(Entries::EntryGuard.weekly_contract?(pick: pick, index_cfg: index_cfg)).to be false
    end
  end

  describe '.exposure_ok? (Pyramiding)' do
    it 'allows first position' do
      expect(Entries::EntryGuard.exposure_ok?(instrument: instrument, side: 'LONG', max_same_side: 2)).to be true
    end

    context 'with one existing position' do
      let!(:first_pos) { create(:position_tracker, :active, instrument: instrument, side: 'LONG', segment: 'NSE_FNO', entry_price: 100, quantity: 50) }

      it 'blocks second position if first is in loss' do
        # Mock PnL to be negative
        allow_any_instance_of(PositionTracker).to receive(:last_pnl_rupees).and_return(-100)
        expect(Entries::EntryGuard.exposure_ok?(instrument: instrument, side: 'LONG', max_same_side: 2)).to be false
      end

      it 'allows second position if first is in profit and old enough' do
        # Mock PnL to be positive
        allow_any_instance_of(PositionTracker).to receive(:last_pnl_rupees).and_return(500)
        # Mock updated_at to be old enough
        first_pos.update_columns(updated_at: 10.minutes.ago)
        expect(Entries::EntryGuard.exposure_ok?(instrument: instrument, side: 'LONG', max_same_side: 2)).to be true
      end

      it 'blocks second position if first is in profit but too fresh' do
        allow_any_instance_of(PositionTracker).to receive(:last_pnl_rupees).and_return(500)
        first_pos.update_columns(updated_at: 1.minute.ago)
        expect(Entries::EntryGuard.exposure_ok?(instrument: instrument, side: 'LONG', max_same_side: 2)).to be false
      end
    end
  end

  describe '.banknifty_last_week?' do
    let(:bn_instrument) { create(:instrument, symbol_name: 'BANKNIFTY', exchange: :nse, segment: :index) }

    it 'returns true if today is within 7 days of monthly expiry' do
      # Mock monthly expiry to be next Wednesday
      expiry = Time.zone.today + 3.days
      allow(Entries::EntryGuard).to receive(:banknifty_monthly_expiry).and_return(expiry)
      expect(Entries::EntryGuard.banknifty_last_week?(instrument: bn_instrument)).to be true
    end

    it 'returns false if monthly expiry is far away' do
      expiry = Time.zone.today + 15.days
      allow(Entries::EntryGuard).to receive(:banknifty_monthly_expiry).and_return(expiry)
      expect(Entries::EntryGuard.banknifty_last_week?(instrument: bn_instrument)).to be false
    end
  end

  describe '.daily_limits_allow_entry? (Institutional Rule)' do
    before do
      allow(Entries::EntryGuard).to receive(:daily_limits_enabled?).and_return(true)
    end

    it 'blocks if 3 trades already done for NIFTY' do
      mock_limits = instance_double(Live::DailyLimits)
      allow(Live::DailyLimits).to receive(:new).and_return(mock_limits)
      allow(mock_limits).to receive(:can_trade?).and_return({ allowed: true })
      allow(mock_limits).to receive(:get_daily_trades).with('NIFTY').and_return(3)

      expect(Entries::EntryGuard.daily_limits_allow_entry?(index_cfg: { key: 'NIFTY' })).to be false
    end

    it 'allows if less than 3 trades done' do
      mock_limits = instance_double(Live::DailyLimits)
      allow(Live::DailyLimits).to receive(:new).and_return(mock_limits)
      allow(mock_limits).to receive(:can_trade?).and_return({ allowed: true })
      allow(mock_limits).to receive(:get_daily_trades).with('NIFTY').and_return(1)

      expect(Entries::EntryGuard.daily_limits_allow_entry?(index_cfg: { key: 'NIFTY' })).to be true
    end
  end

  describe '.resolve_entry_ltp' do
    let(:hub) { Live::MarketFeedHub.instance }

    before do
      allow(hub).to receive_messages(running?: true, connected?: true, subscribe: true)
    end

    it 'returns cached LTP if available' do
      allow(Live::TickQuery).to receive(:for_security).and_return(double('Tick', ltp: 155.5))
      expect(Entries::EntryGuard.resolve_entry_ltp(instrument: instrument, pick: pick, index_cfg: index_cfg)).to eq(155.5)
    end

    it 'falls back to API if WebSocket tick timeout' do
      allow(Live::TickQuery).to receive(:for_security).and_return(nil)
      allow(instrument).to receive(:fetch_ltp_from_api_for_segment).and_return(160.0)
      # Speed up the test by mocking sleep
      allow(Entries::EntryGuard).to receive(:sleep)

      expect(Entries::EntryGuard.resolve_entry_ltp(instrument: instrument, pick: pick, index_cfg: index_cfg)).to eq(160.0)
    end
  end
end
