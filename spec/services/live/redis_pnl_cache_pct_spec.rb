# frozen_string_literal: true

require 'rails_helper'

# Redis PnL Cache - Percentage Format Consistency
#
# Documents and verifies the decimal/percentage format contract for every
# field stored in the Redis pnl:tracker:<id> hash.
#
# Format contract:
#   pnl_pct        → DECIMAL  (e.g. 0.30 for 30%)   ← used by exit rules
#   hwm_pnl_pct    → DECIMAL  (e.g. 0.45 for 45%)   ← used by trailing stop
#   price_change_pct → PERCENTAGE (e.g. 30.0 for 30%) ← display-only field
#   drawdown_pct   → PERCENTAGE (e.g. 15.0 for 15% drawdown from HWM) ← display-only
#   pnl            → absolute ₹ (not a percentage)
#   hwm_pnl        → absolute ₹ high-water mark (not a percentage)
#   ltp            → absolute price
#
RSpec.describe Live::RedisPnlCache, type: :integration do
  subject(:cache) { described_class.instance }

  let(:tracker_id) { 99_999 } # Use a large ID to avoid collisions with other specs

  # Build a minimal tracker double that store_pnl accepts
  let(:tracker_double) do
    instance_double(
      PositionTracker,
      entry_price: BigDecimal('100.0'),
      quantity: 75,
      segment: 'NSE_FNO',
      security_id: '50073',
      symbol: 'NIFTY-CE',
      side: 'long_ce',
      order_no: 'TEST99999',
      paper?: false,
      created_at: 1.hour.ago,
      meta: {}
    )
  end

  before do
    cache.clear_tracker(tracker_id)
    allow(Positions::MetadataResolver).to receive(:index_key).and_return('NIFTY')
    allow(Positions::MetadataResolver).to receive(:direction).and_return('long')
  end

  after do
    cache.clear_tracker(tracker_id)
  end

  # ─────────────────────────────────────────────────────────────────────────
  # pnl_pct: stored and fetched as DECIMAL
  # ─────────────────────────────────────────────────────────────────────────
  describe '#store_pnl / #fetch_pnl — pnl_pct field' do
    it 'round-trips pnl_pct as DECIMAL (0.30 stored → 0.30 fetched)' do
      cache.store_pnl(tracker_id: tracker_id, pnl: 2250.0, ltp: 130.0, hwm: 2250.0, pnl_pct: 0.30)

      result = cache.fetch_pnl(tracker_id)
      expect(result).not_to be_nil
      expect(result[:pnl_pct]).to be_within(0.0001).of(0.30)
    end

    it 'round-trips negative pnl_pct as DECIMAL (-0.12 stored → -0.12 fetched)' do
      cache.store_pnl(tracker_id: tracker_id, pnl: -900.0, ltp: 88.0, hwm: 0.0, pnl_pct: -0.12)

      result = cache.fetch_pnl(tracker_id)
      expect(result[:pnl_pct]).to be_within(0.0001).of(-0.12)
    end

    it 'stores pnl_pct < 1.0 for a 30% gain (not 30.0)' do
      cache.store_pnl(tracker_id: tracker_id, pnl: 2250.0, ltp: 130.0, hwm: 2250.0, pnl_pct: 0.30)

      result = cache.fetch_pnl(tracker_id)
      expect(result[:pnl_pct]).to be < 1.0
    end

    it 'stores pnl_pct > -1.0 for a 12% loss (not -12.0)' do
      cache.store_pnl(tracker_id: tracker_id, pnl: -900.0, ltp: 88.0, hwm: 0.0, pnl_pct: -0.12)

      result = cache.fetch_pnl(tracker_id)
      expect(result[:pnl_pct]).to be > -1.0
    end
  end

  # ─────────────────────────────────────────────────────────────────────────
  # hwm_pnl_pct: stored and fetched as DECIMAL
  # ─────────────────────────────────────────────────────────────────────────
  describe '#store_pnl / #fetch_pnl — hwm_pnl_pct field' do
    it 'round-trips hwm_pnl_pct as DECIMAL (0.45 → 0.45)' do
      cache.store_pnl(
        tracker_id: tracker_id, pnl: 2250.0, ltp: 130.0, hwm: 3375.0,
        pnl_pct: 0.30, hwm_pnl_pct: 0.45
      )

      result = cache.fetch_pnl(tracker_id)
      expect(result[:hwm_pnl_pct]).to be_within(0.0001).of(0.45)
      expect(result[:hwm_pnl_pct]).to be < 1.0 # DECIMAL
    end
  end

  # ─────────────────────────────────────────────────────────────────────────
  # price_change_pct: stored as PERCENTAGE (* 100) — display-only field
  # IMPORTANT: This field is PERCENTAGE format unlike pnl_pct which is DECIMAL
  # ─────────────────────────────────────────────────────────────────────────
  describe '#store_pnl / #fetch_pnl — price_change_pct field (PERCENTAGE format)' do
    it 'stores price_change_pct as PERCENTAGE (30.0) when ltp is 130 and entry is 100' do
      cache.store_pnl(
        tracker_id: tracker_id, pnl: 2250.0, ltp: 130.0, hwm: 2250.0,
        pnl_pct: 0.30, tracker: tracker_double
      )

      result = cache.fetch_pnl(tracker_id)
      # price_change_pct = (130 - 100) / 100 * 100 = 30.0  (PERCENTAGE)
      expect(result[:price_change_pct]).to be_within(0.01).of(30.0)
      expect(result[:price_change_pct]).to be > 1.0 # NOT decimal (0.30), it's 30.0
    end

    it 'price_change_pct differs from pnl_pct by factor of 100 (different units)' do
      cache.store_pnl(
        tracker_id: tracker_id, pnl: 2250.0, ltp: 130.0, hwm: 2250.0,
        pnl_pct: 0.30, tracker: tracker_double
      )

      result = cache.fetch_pnl(tracker_id)
      ratio = result[:price_change_pct] / result[:pnl_pct]
      expect(ratio).to be_within(0.1).of(100.0)
    end
  end

  # ─────────────────────────────────────────────────────────────────────────
  # drawdown_pct: stored as PERCENTAGE (* 100) — display-only field
  # ─────────────────────────────────────────────────────────────────────────
  describe '#store_pnl / #fetch_pnl — drawdown_pct field (PERCENTAGE format)' do
    it 'stores drawdown_pct as PERCENTAGE when there is a drawdown from HWM' do
      # HWM = 3000 ₹, current PnL = 2250 ₹ → drawdown = 750 ₹ = 25% of HWM
      cache.store_pnl(
        tracker_id: tracker_id, pnl: 2250.0, ltp: 130.0, hwm: 3000.0,
        pnl_pct: 0.30, tracker: tracker_double
      )

      result = cache.fetch_pnl(tracker_id)
      # drawdown_pct = (3000 - 2250) / 3000 * 100 = 25.0 (PERCENTAGE)
      expect(result[:drawdown_pct]).to be_within(0.1).of(25.0)
      expect(result[:drawdown_pct]).to be > 1.0 # NOT decimal (0.25), it's 25.0
    end

    it 'stores drawdown_rupees as absolute ₹' do
      cache.store_pnl(
        tracker_id: tracker_id, pnl: 2250.0, ltp: 130.0, hwm: 3000.0,
        pnl_pct: 0.30, tracker: tracker_double
      )

      result = cache.fetch_pnl(tracker_id)
      expect(result[:drawdown_rupees]).to be_within(0.01).of(750.0)
    end
  end

  # ─────────────────────────────────────────────────────────────────────────
  # Absolute fields: pnl, hwm_pnl, ltp are ₹ values (not percentages)
  # ─────────────────────────────────────────────────────────────────────────
  describe '#store_pnl / #fetch_pnl — absolute ₹ fields' do
    before do
      cache.store_pnl(
        tracker_id: tracker_id, pnl: 2250.0, ltp: 130.0, hwm: 3000.0,
        pnl_pct: 0.30
      )
    end

    it 'round-trips pnl as absolute ₹' do
      result = cache.fetch_pnl(tracker_id)
      expect(result[:pnl]).to be_within(0.01).of(2250.0)
    end

    it 'round-trips ltp as absolute price' do
      result = cache.fetch_pnl(tracker_id)
      expect(result[:ltp]).to be_within(0.01).of(130.0)
    end

    it 'round-trips hwm_pnl as absolute ₹' do
      result = cache.fetch_pnl(tracker_id)
      expect(result[:hwm_pnl]).to be_within(0.01).of(3000.0)
    end
  end

  # ─────────────────────────────────────────────────────────────────────────
  # last-wins semantics: subsequent store overwrites previous
  # ─────────────────────────────────────────────────────────────────────────
  describe 'last-wins update semantics' do
    it 'overwrites pnl_pct with the latest value' do
      cache.store_pnl(tracker_id: tracker_id, pnl: 750.0, ltp: 110.0, hwm: 750.0, pnl_pct: 0.10)
      cache.store_pnl(tracker_id: tracker_id, pnl: 2250.0, ltp: 130.0, hwm: 2250.0, pnl_pct: 0.30)

      result = cache.fetch_pnl(tracker_id)
      expect(result[:pnl_pct]).to be_within(0.0001).of(0.30)
    end

    it 'reflects latest ltp after tick update' do
      cache.store_pnl(tracker_id: tracker_id, pnl: 750.0, ltp: 110.0, hwm: 750.0, pnl_pct: 0.10)
      cache.store_pnl(tracker_id: tracker_id, pnl: 1500.0, ltp: 120.0, hwm: 1500.0, pnl_pct: 0.20)

      result = cache.fetch_pnl(tracker_id)
      expect(result[:ltp]).to be_within(0.01).of(120.0)
    end
  end

  # ─────────────────────────────────────────────────────────────────────────
  # Missing key behaviour: fetch_pnl returns nil for unknown tracker
  # ─────────────────────────────────────────────────────────────────────────
  describe '#fetch_pnl' do
    it 'returns nil for a tracker with no cached data' do
      cache.clear_tracker(tracker_id)
      expect(cache.fetch_pnl(tracker_id)).to be_nil
    end
  end

  # ─────────────────────────────────────────────────────────────────────────
  # compute_pnl_pct (PnlCache module on RiskManagerService) returns DECIMAL
  # ─────────────────────────────────────────────────────────────────────────
  describe 'compute_pnl_pct (internal formula)' do
    let(:service) { Live::RiskManagerService.new }
    let(:instrument) { create(:instrument, :nifty_future, security_id: '9998') }
    let(:tracker) do
      create(
        :position_tracker,
        instrument: instrument,
        watchable: instrument,
        entry_price: 100.0,
        quantity: 75,
        segment: 'NSE_FNO',
        security_id: '9998',
        status: 'active'
      )
    end

    before do
      allow(Live::MarketFeedHub).to receive(:instance).and_return(
        instance_double(Live::MarketFeedHub,
                        running?: true, subscribed?: false,
                        subscribe: true, unsubscribe: true, start!: true)
      )
    end

    it 'returns DECIMAL (< 1.0) for a 30% gain' do
      result = service.send(:compute_pnl_pct, tracker, BigDecimal('130.0'))
      expect(result).to be_within(BigDecimal('0.0001')).of(BigDecimal('0.30'))
      expect(result).to be < 1
    end

    it 'returns negative DECIMAL for a loss' do
      result = service.send(:compute_pnl_pct, tracker, BigDecimal('88.0'))
      expect(result).to be_within(BigDecimal('0.0001')).of(BigDecimal('-0.12'))
      expect(result).to be > -1
    end

    it 'returns nil when entry_price is zero' do
      allow(tracker).to receive(:entry_price).and_return(0)
      allow(tracker).to receive(:avg_price).and_return(0)
      result = service.send(:compute_pnl_pct, tracker, BigDecimal('130.0'))
      expect(result).to be_nil
    end
  end

  # ─────────────────────────────────────────────────────────────────────────
  # DB sync: last_pnl_pct stored as DECIMAL BigDecimal
  # ─────────────────────────────────────────────────────────────────────────
  describe 'DB sync — last_pnl_pct stored as DECIMAL' do
    let(:instrument) { create(:instrument, :nifty_future, security_id: '9997') }
    let(:tracker) do
      create(
        :position_tracker,
        instrument: instrument,
        watchable: instrument,
        entry_price: 100.0,
        quantity: 75,
        segment: 'NSE_FNO',
        security_id: '9997',
        status: 'active'
      )
    end

    before do
      allow(Live::MarketFeedHub).to receive(:instance).and_return(
        instance_double(Live::MarketFeedHub,
                        running?: true, subscribed?: false,
                        subscribe: true, unsubscribe: true, start!: true)
      )
    end

    it 'stores last_pnl_pct as DECIMAL in the database' do
      cache.sync_pnl_to_database(tracker.id, BigDecimal('2250.0'), BigDecimal('0.30'), BigDecimal('2250.0'))

      tracker.reload
      expect(tracker.last_pnl_pct).not_to be_nil
      expect(tracker.last_pnl_pct).to be_within(BigDecimal('0.0001')).of(BigDecimal('0.30'))
      expect(tracker.last_pnl_pct).to be < 1 # DECIMAL, not PERCENTAGE
    end

    it 'stores last_pnl_pct as negative DECIMAL for a loss' do
      cache.sync_pnl_to_database(tracker.id, BigDecimal('-900.0'), BigDecimal('-0.12'), BigDecimal('0.0'))

      tracker.reload
      expect(tracker.last_pnl_pct).to be_within(BigDecimal('0.0001')).of(BigDecimal('-0.12'))
      expect(tracker.last_pnl_pct).to be > -1 # DECIMAL, not PERCENTAGE
    end
  end
end
