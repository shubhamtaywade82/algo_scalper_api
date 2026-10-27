# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Reports::MarketBrief::SnapshotBuilder do
  subject(:snapshot) { described_class.call }

  before do
    travel_to(brief_market_open_time)
    stub_market_brief_sources
  end

  def index(key)
    snapshot['indices'].find { |i| i['index_key'] == key }
  end

  describe 'complete live snapshot' do
    it 'stamps schema, trading date, timezone and mode' do
      expect(snapshot).to include(
        'schema_version' => 1, 'trading_date' => '2026-10-27', 'timezone' => 'Asia/Kolkata', 'mode' => 'paper'
      )
      expect(snapshot.dig('session', 'status')).to eq('open')
    end

    it 'reports live quotes with a change derived from the real previous close' do
      quote = index('NIFTY')['quote']
      expect(quote).to include('status' => 'live', 'ltp' => 24_500.5, 'prev_close' => 24_400.0, 'change_pct' => 0.41)
      expect(quote['age_seconds']).to eq(2)
    end

    it 'maps regime, SMC and multi-timeframe evidence into explicit bias labels' do
      nifty = index('NIFTY')
      expect(nifty['regime']).to include('status' => 'fresh', 'label' => 'TRENDING_UP', 'adx' => 31.42)
      expect(nifty['smc']['decision']).to eq('CALL')
      expect(nifty.dig('smc', 'timeframes', 'ltf')).to include('trend' => 'BULLISH', 'zone' => 'DISCOUNT',
                                                               'active_fvg_count' => 1, 'liquidity_sweep' => true)
      expect(nifty['bias']).to eq('technical' => 'BULLISH', 'smc' => 'BULLISH',
                                  'mtf_alignment' => 'ALIGNED_BULLISH', 'agreement' => 'AGREE')
    end

    it 'never fabricates a Supertrend value it has no cross-process source for' do
      expect(index('NIFTY')['supertrend']).to eq('status' => 'unavailable',
                                                 'reason' => 'no_cross_process_supertrend_snapshot')
    end

    it 'reports unsupported context sources as unavailable instead of approximating them' do
      expect(snapshot.dig('market_context', 'unavailable')).to include('fii_dii_flows', 'market_breadth', 'news')
      expect(snapshot.dig('market_context', 'vix')).to include('status' => 'ok', 'value' => 13.25, 'entry_allowed' => true)
    end

    it 'rates overall freshness live when every critical source is fresh' do
      expect(snapshot['freshness']['state']).to eq('live')
      expect(snapshot.dig('health', 'components', 'market_feed', 'status')).to eq('ok')
    end
  end

  describe 'stale and missing data' do
    it 'marks an old tick stale during the session (never live)' do
      stub_market_brief_sources(quote_age: 2.minutes)
      expect(index('NIFTY')['quote']['status']).to eq('stale')
      expect(snapshot['warnings']).to include('NIFTY_quote_stale')
      expect(snapshot['freshness']['state']).to eq('partial')
    end

    it 'reports a missing quote as unavailable with nil values, not zero' do
      allow(Live::TickQuery).to receive(:for_security).and_return(nil)
      expect(index('SENSEX')['quote']).to eq('status' => 'unavailable')
    end

    it 'treats a stale analysis entry as stale and an empty regime as unavailable' do
      stub_market_brief_sources(regime: brief_regime_entry(label: 'NO_DATA', fresh: false),
                                smc: brief_smc_entry(fresh: false))
      expect(index('NIFTY')['regime']['status']).to eq('unavailable')
      expect(index('NIFTY')['smc']['status']).to eq('stale')
      expect(index('NIFTY')['bias']['technical']).to eq('UNAVAILABLE')
    end

    it 'surfaces technical vs SMC conflict instead of resolving it' do
      stub_market_brief_sources(regime: brief_regime_entry(label: 'TRENDING_DOWN'), smc: brief_smc_entry(decision: :call))
      expect(index('NIFTY')['bias']['agreement']).to eq('CONFLICT')
    end

    it 'isolates a failing source to its own section' do
      allow(Risk::CircuitBreaker.instance).to receive(:status).and_raise(Redis::CannotConnectError)
      expect(snapshot['risk']).to eq('status' => 'error', 'error' => 'Redis::CannotConnectError')
      expect(snapshot['warnings']).to include('risk_unavailable')
      expect(snapshot.dig('setup', 'blockers')).to include('risk_state_unavailable')
      expect(index('NIFTY')['quote']['status']).to eq('live')
    end
  end

  describe 'closed market' do
    it 'labels last-session quotes as last_session after the close' do
      travel_to(Time.find_zone('Asia/Kolkata').local(2026, 10, 27, 16, 5))
      expect(snapshot.dig('session', 'status')).to eq('post_close')
      expect(index('NIFTY')['quote']['status']).to eq('last_session')
      expect(snapshot['freshness']['state']).to eq('market_closed')
    end

    it 'identifies an exchange holiday' do
      allow(Market::Calendar).to receive(:trading_day?).and_return(false)
      create(:market_holiday, exchange: 'nse', observed_on: Date.new(2026, 10, 27), name: 'Test Holiday')
      expect(snapshot['session']).to include('status' => 'holiday', 'holiday_name' => 'Test Holiday')
      expect(snapshot.dig('setup', 'decision')).to eq('BLOCKED')
    end
  end

  describe 'risk and health' do
    it 'reports active exposure, P&L and loss-limit utilization for the current mode only' do
      create(:position_tracker, paper: true, entry_price: 120, quantity: 75, last_pnl_rupees: 0)
      create(:position_tracker, paper: false, entry_price: 999, quantity: 75)
      stub_market_brief_sources(daily_loss: 1_000.0)

      risk = snapshot['risk']
      expect(risk['active_positions_count']).to eq(1)
      expect(risk['exposure_rupees']).to eq(9_000.0)
      expect(risk['exposure_pct_of_capital']).to eq(9.0)
      expect(risk['daily_loss']).to include('realized_loss_rupees' => 1_000.0, 'utilization_pct' => 25.0,
                                            'basis' => 'realized_only')
    end

    it 'shows a down feed heartbeat as down, not as running' do
      stub_market_brief_sources(feed_alive: false, scheduler_alive: false)
      components = snapshot.dig('health', 'components')
      expect(components['market_feed']['status']).to eq('down')
      expect(components['trading_daemon']['status']).to eq('not_observed')
      expect(snapshot['health']['status']).to eq('degraded')
    end

    it 'surfaces unresolved reconciliation discrepancies' do
      run = create(:reconciliation_run, status: 'passed', completed_at: 1.minute.ago)
      create(:reconciliation_discrepancy, reconciliation_run: run, resolution: nil)
      expect(snapshot.dig('health', 'components', 'reconciliation', 'status')).to eq('discrepancies')
      expect(snapshot.dig('risk', 'reconciliation_discrepancies', 'unresolved_count')).to eq(1)
    end
  end

  describe 'read-only guarantee' do
    it 'does not touch the order gateway or create trackers' do
      expect(Orders.config.gateway).not_to receive(:place_market) if Orders.config.gateway.respond_to?(:place_market)
      expect { snapshot }.not_to change(PositionTracker, :count)
    end
  end

  describe '.digest' do
    it 'ignores generation time and derived ages but changes when a fact changes' do
      base = snapshot
      aged = base.deep_dup.merge('generated_at' => 1.minute.from_now.iso8601)
      aged['indices'][0]['quote']['age_seconds'] = 999
      moved = base.deep_dup
      moved['indices'][0]['quote']['ltp'] = 24_510.0

      expect(described_class.digest(aged)).to eq(described_class.digest(base))
      expect(described_class.digest(moved)).not_to eq(described_class.digest(base))
    end
  end
end
