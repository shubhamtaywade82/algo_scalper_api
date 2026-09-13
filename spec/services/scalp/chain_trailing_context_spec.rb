# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Scalp::ChainTrailingContext do
  let(:instrument) do
    instance_double(
      Instrument,
      strike_price: 24_500.0,
      option_type: 'CE',
      expiry_date: Date.new(2026, 9, 17),
      fetch_option_chain: chain
    )
  end

  # Spot 24,495 — just 5 pts below the 24,500 CE wall (0.02% < 0.3% buffer).
  # Own strike 24,500 CE: OI 1_000_000, IV 18, volume 5_000.
  let(:chain) do
    {
      last_price: 24_495.0,
      oc: {
        '24400.0' => { 'ce' => { 'oi' => 100_000, 'implied_volatility' => 16.0 }, 'pe' => { 'oi' => 90_000 } },
        '24500.0' => { 'ce' => { 'oi' => 1_000_000, 'implied_volatility' => 18.0, 'volume' => 5_000 }, 'pe' => { 'oi' => 120_000 } },
        '24600.0' => { 'ce' => { 'oi' => 700_000, 'implied_volatility' => 15.0 }, 'pe' => { 'oi' => 150_000 } }
      }
    }
  end

  let(:tracker) do
    instance_double(
      PositionTracker,
      id: 7,
      instrument: instrument,
      iv_at_entry: 20.0,
      entry_price: 120.0,
      quantity: 50,
      meta: {},
      direction: 'long_ce',
      expiry_date: Date.new(2026, 9, 17)
    )
  end

  # hwm_pnl 600 on entry_value 6,000 -> peak 10% (>= 2% wall minimum).
  let(:snapshot) { { ltp: 132.0, pnl_pct: 0.10, pnl: 600.0, hwm_pnl: 600.0 } }

  let(:pos_data) do
    double(position_direction: 'long_ce', price_history: [120.0, 121.0], underlying_segment: nil, underlying_security_id: nil)
  end

  before do
    described_class.reset_cache!
    allow(AlgoConfig).to receive(:fetch).and_return({
      risk: { scalp_exit: { enabled: true, chain_context: { enabled: true } } }
    })
    allow(Positions::ActiveCache.instance).to receive(:get_by_tracker_id).with(7).and_return(pos_data)
    allow(tracker).to receive(:update_column)
    allow(Rails.logger).to receive_messages(error: nil, warn: nil, info: nil, debug: nil)
  end

  # Force the TTL-cached evaluation to be stale so the next evaluate recomputes
  # (tests run in milliseconds; the 15s TTL would otherwise return cached results).
  def force_stale!
    entry = described_class.instance_variable_get(:@cache)&.[](tracker.id)
    entry[:at] = -Float::INFINITY if entry
  end

  describe '.enabled?' do
    it 'requires the parent scalp_exit opt-in' do
      allow(AlgoConfig).to receive(:fetch).and_return({ risk: {} })
      expect(described_class.enabled?).to be false
    end

    it 'can be disabled independently of the parent' do
      allow(AlgoConfig).to receive(:fetch).and_return({
        risk: { scalp_exit: { enabled: true, chain_context: { enabled: false } } }
      })
      expect(described_class.enabled?).to be false
    end
  end

  describe '.evaluate — availability' do
    it 'holds when the tracker has no instrument' do
      allow(tracker).to receive(:instrument).and_return(nil)
      expect(described_class.evaluate(tracker, snapshot)).to eq({ action: :hold, multiplier: 1.0, reason: nil })
    end

    it 'holds when the chain fetch returns nil' do
      allow(instrument).to receive(:fetch_option_chain).and_return(nil)
      expect(described_class.evaluate(tracker, snapshot)).to eq({ action: :hold, multiplier: 1.0, reason: nil })
    end

    it 'holds when the own strike is missing from the chain' do
      allow(instrument).to receive(:strike_price).and_return(29_999.0)
      expect(described_class.evaluate(tracker, snapshot)).to eq({ action: :hold, multiplier: 1.0, reason: nil })
    end

    it 'degrades to hold (never raises) when the chain fetch blows up' do
      allow(instrument).to receive(:fetch_option_chain).and_raise(RuntimeError, 'boom')
      expect(described_class.evaluate(tracker, snapshot)).to eq({ action: :hold, multiplier: 1.0, reason: nil })
      expect(Rails.logger).to have_received(:error).with(/evaluate failed for tracker=7/)
    end
  end

  describe '.evaluate — IV collapse' do
    it 'exits when own-strike IV drops past the threshold vs entry IV' do
      # entry IV 20 -> current 15 = 25% drop >= 15%
      chain[:oc]['24500.0']['ce']['implied_volatility'] = 15.0
      # Move spot away from the wall so the wall signal cannot preempt (wall at
      # 24500 is ABOVE spot -> bullish direction still checks it; push spot low).
      chain[:last_price] = 24_100.0

      result = described_class.evaluate(tracker, snapshot)
      expect(result[:action]).to eq(:exit)
      expect(result[:reason]).to include('SCALP_IV_COLLAPSE')
      expect(result[:reason]).to include('20.0 -> 15.0')
    end

    it 'does not fire on a shallow IV dip' do
      chain[:oc]['24500.0']['ce']['implied_volatility'] = 18.5 # 7.5% drop
      chain[:last_price] = 24_100.0

      result = described_class.evaluate(tracker, snapshot)
      expect(result[:action]).to eq(:hold)
    end

    it 'does not fire without an entry IV snapshot' do
      allow(tracker).to receive(:iv_at_entry).and_return(nil)
      chain[:last_price] = 24_100.0

      expect(described_class.evaluate(tracker, snapshot)[:action]).to eq(:hold)
    end
  end

  describe '.evaluate — gamma wall' do
    it 'exits into the wall when spot is within the buffer and peak covers fees' do
      # default fixture: spot 24,495, bullish wall 24,500 (max CE OI above spot)
      result = described_class.evaluate(tracker, snapshot)
      expect(result[:action]).to eq(:exit)
      expect(result[:reason]).to include('SCALP_GAMMA_WALL_APPROACH')
      expect(result[:reason]).to include('24500.0')
    end

    it 'ignores walls behind the position direction' do
      # bearish position: the wall is max PE OI BELOW spot; fixture has none near
      allow(pos_data).to receive(:position_direction).and_return('long_pe')
      chain[:oc]['24400.0']['pe']['oi'] = 2_000_000 # far below, 95 pts away > buffer

      result = described_class.evaluate(tracker, snapshot)
      expect(result[:action]).to eq(:hold)
    end

    it 'does not bank into the wall before the peak covers fees' do
      poor_snapshot = { ltp: 122.0, pnl_pct: 0.01, pnl: 60.0, hwm_pnl: 60.0 } # peak 1% < 2%
      result = described_class.evaluate(tracker, poor_snapshot)
      expect(result[:action]).to eq(:hold)
    end

    it 'ignores a distant wall' do
      chain[:last_price] = 24_200.0 # wall 300 pts away
      result = described_class.evaluate(tracker, snapshot)
      expect(result[:action]).to eq(:hold)
    end
  end

  describe '.evaluate — OI drift' do
    before { chain[:last_price] = 24_100.0 } # away from the wall

    it 'records the baseline on first evaluation and holds' do
      expect(described_class.evaluate(tracker, snapshot)).to eq({ action: :hold, multiplier: 1.0, reason: nil })
      expect(tracker).to have_received(:update_column).with(:meta, hash_including('scalp_oi_baseline' => 1_000_000))
    end

    it 'tightens when OI unwinds past the threshold' do
      described_class.evaluate(tracker, snapshot) # baseline: 1_000_000
      force_stale!

      allow(tracker).to receive(:meta).and_return({ 'scalp_oi_baseline' => 1_000_000 })
      chain[:oc]['24500.0']['ce']['oi'] = 850_000 # -15% <= -10%

      result = described_class.evaluate(tracker, { ltp: 130.0, pnl_pct: 0.08, pnl: 500.0, hwm_pnl: 600.0 })
      expect(result[:action]).to eq(:tighten)
      expect(result[:multiplier]).to eq(0.5)
      expect(result[:reason]).to include('SCALP_OI_UNWIND')
      expect(result[:reason]).to include('1000000 -> 850000')
    end

    it 'tightens when fresh writing pins the strike while flat' do
      described_class.evaluate(tracker, snapshot)
      force_stale!

      allow(tracker).to receive(:meta).and_return({ 'scalp_oi_baseline' => 1_000_000 })
      chain[:oc]['24500.0']['ce']['oi'] = 1_200_000 # +20% >= +15%

      result = described_class.evaluate(tracker, { ltp: 118.0, pnl_pct: -0.01, pnl: -60.0, hwm_pnl: 600.0 })
      expect(result[:action]).to eq(:tighten)
      expect(result[:reason]).to include('SCALP_OI_WRITING')
    end

    it 'ignores writing when the position is already profitable' do
      described_class.evaluate(tracker, snapshot)
      force_stale!

      allow(tracker).to receive(:meta).and_return({ 'scalp_oi_baseline' => 1_000_000 })
      chain[:oc]['24500.0']['ce']['oi'] = 1_200_000

      result = described_class.evaluate(tracker, { ltp: 140.0, pnl_pct: 0.17, pnl: 1_000.0, hwm_pnl: 1_000.0 })
      expect(result[:action]).to eq(:hold)
    end
  end

  describe '.evaluate — convexity widening' do
    before do
      chain[:last_price] = 24_100.0 # away from the wall
      allow(tracker).to receive(:meta).and_return({ 'scalp_oi_baseline' => 1_000_000 })
      allow(pos_data).to receive_messages(underlying_segment: 'IDX_I', underlying_security_id: '13')
    end

    def underlying_tick(ltp)
      MarketTick.new(
        segment: 'IDX_I', security_id: '13', ltp: ltp,
        timestamp: Time.current, oi: 0, oi_change: 0, bid: 0.0, ask: 0.0, volume: 0, prev_close: 0.0
      )
    end

    it 'widens when the premium amplifies a favourable underlying move' do
      # Evaluation 1 seeds the underlying history at 24,000.
      allow(Live::TickQuery).to receive(:for_security).and_return(underlying_tick(24_000.0))
      described_class.evaluate(tracker, snapshot)
      force_stale!

      # Evaluation 2: underlying +0.1% (24,000 -> 24,024), premium 120 -> 132 (+10%)
      # -> ratio 100 >= 8, direction favourable for a long CE.
      allow(Live::TickQuery).to receive(:for_security).and_return(underlying_tick(24_024.0))
      allow(pos_data).to receive(:price_history).and_return([120.0, 132.0])

      result = described_class.evaluate(tracker, snapshot)
      expect(result[:action]).to eq(:widen)
      expect(result[:multiplier]).to eq(1.2)
      expect(result[:reason]).to include('SCALP_CONVEXITY')
      expect(result[:reason]).to include('ratio 100.0')
    end

    it 'does not widen on an unfavourable underlying move (PE-shaped protection)' do
      allow(Live::TickQuery).to receive(:for_security).and_return(underlying_tick(24_000.0))
      described_class.evaluate(tracker, snapshot)
      force_stale!

      # Underlying moved UP (unfavourable for a long CE) while premium rose —
      # that is vega, not momentum amplification.
      allow(Live::TickQuery).to receive(:for_security).and_return(underlying_tick(24_024.0))
      allow(pos_data).to receive(:price_history).and_return([120.0, 132.0])
      allow(pos_data).to receive(:position_direction).and_return('long_pe')

      result = described_class.evaluate(tracker, snapshot)
      expect(result[:action]).to eq(:hold)
    end

    it 'does not widen on a weak amplification ratio' do
      allow(Live::TickQuery).to receive(:for_security).and_return(underlying_tick(24_000.0))
      described_class.evaluate(tracker, snapshot)
      force_stale!

      # Underlying +1% while premium +2% -> ratio 2 < 8.
      allow(Live::TickQuery).to receive(:for_security).and_return(underlying_tick(24_240.0))
      allow(pos_data).to receive(:price_history).and_return([120.0, 122.4])

      result = described_class.evaluate(tracker, snapshot)
      expect(result[:action]).to eq(:hold)
    end
  end

  describe 'TTL caching' do
    it 'reuses the cached result within the TTL' do
      chain[:last_price] = 24_100.0
      allow(instrument).to receive(:fetch_option_chain).and_return(chain)

      first = described_class.evaluate(tracker, snapshot)
      allow(instrument).to receive(:fetch_option_chain).and_raise(RuntimeError, 'should not refetch')

      second = described_class.evaluate(tracker, snapshot)
      expect(second).to eq(first)
    end

    it 'strictly validates numeric config' do
      allow(AlgoConfig).to receive(:fetch).and_return({
        risk: { scalp_exit: { enabled: true, chain_context: { enabled: true, oi_unwind_pct: 'tiny' } } }
      })
      allow(tracker).to receive(:meta).and_return({ 'scalp_oi_baseline' => 1_000_000 })
      chain[:last_price] = 24_100.0
      chain[:oc]['24500.0']['ce']['oi'] = 800_000

      # Garbage config is caught by the isolation rescue, logged, degraded to hold.
      expect(described_class.evaluate(tracker, snapshot)[:action]).to eq(:hold)
      expect(Rails.logger).to have_received(:error).with(/ConfigurationError.*oi_unwind_pct/)
    end
  end
end
