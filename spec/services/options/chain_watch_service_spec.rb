require 'rails_helper'

RSpec.describe Options::ChainWatchService do
  let(:index_cfg) { { key: 'NIFTY', segment: 'IDX_I', sid: '13' } }
  let(:expiry) { Date.current + 7.days }

  before do
    allow(IndexConfigLoader).to receive(:load_indices).and_return([index_cfg])
    allow(Live::MarketFeedHub.instance).to receive(:subscribe_many).and_return([])
    allow(Live::MarketFeedHub.instance).to receive(:unsubscribe_many).and_return([])
    allow(Live::MarketFeedHub.instance).to receive(:unsubscribe).and_return(true)
    allow(Live::PositionIndex.instance).to receive(:trackers_for).and_return([])
  end

  describe '#resolve_atm_legs' do
    it 'returns the 11 nearest strikes both sides of ATM for NIFTY' do
      # Seed 21 CE/PE derivative pairs around strike 24800 in 50pt steps
      instrument = Instrument.create!(
        exchange: 'nse', segment: 'index', security_id: '13',
        symbol_name: 'NIFTY', display_name: 'NIFTY', instrument_code: 'index'
      )
      (-10..10).each do |offset|
        strike = 24800.0 + (offset * 50)
        %w[CE PE].each do |type|
          Derivative.create!(
            instrument: instrument, exchange: 'nse', segment: 'derivatives',
            underlying_symbol: 'NIFTY', expiry_date: expiry, strike_price: strike,
            option_type: type, lot_size: 50, security_id: "#{strike.to_i}#{type}",
            symbol_name: "NIFTY-#{strike.to_i}-#{type}"
          )
        end
      end

      service = described_class.new(index_key: 'NIFTY')
      legs = service.resolve_atm_legs(spot: 24800.0, expiry: expiry)

      expect(legs.size).to eq(22) # 11 strikes × CE/PE
      strikes = legs.map { |l| l[:strike] }.uniq.sort
      expect(strikes).to eq((24550.0..25050.0).step(50).to_a)
    end
  end

  describe '#merge_tick_data' do
    it 'fills LTP/OI/bid/ask from TickQuery and clears feed_stale when a tick exists' do
      legs = [{ strike: 24800.0, type: 'CE', security_id: '24800CE', segment: 'NSE_FNO', feed_stale: true, ltp: nil, oi: nil, bid: nil, ask: nil }]
      tick = MarketTick.new(segment: 'NSE_FNO', security_id: '24800CE', ltp: 120.5, oi: 45_000, oi_change: 1200, bid: 120.0, ask: 121.0, timestamp: Time.current)
      allow(Live::TickQuery).to receive(:for_security).with(segment: 'NSE_FNO', security_id: '24800CE').and_return(tick)

      service = described_class.new(index_key: 'NIFTY')
      result = service.send(:merge_tick_data, legs)

      expect(result.first).to include(ltp: 120.5, oi: 45_000, oi_change: 1200, bid: 120.0, ask: 121.0, feed_stale: false)
    end

    it 'marks feed_stale true when TickQuery returns nil' do
      legs = [{ strike: 24800.0, type: 'CE', security_id: '24800CE', segment: 'NSE_FNO', feed_stale: false, ltp: 100.0, oi: 1, bid: 1, ask: 1 }]
      allow(Live::TickQuery).to receive(:for_security).and_return(nil)

      service = described_class.new(index_key: 'NIFTY')
      result = service.send(:merge_tick_data, legs)

      expect(result.first[:feed_stale]).to be(true)
      expect(result.first[:ltp]).to eq(100.0) # keeps last-known value
    end
  end

  describe '#merge_chain_data' do
    it 'fills OI/IV/greeks from the API chain matching by strike and type' do
      legs = [{ strike: 24800.0, type: 'CE', iv: nil, delta: nil, gamma: nil, theta: nil, vega: nil, oi: nil }]
      api_chain = {
        '24800.000000' => {
          'ce' => { 'oi' => 50_000, 'implied_volatility' => 14.2, 'greeks' => { 'delta' => 0.52, 'gamma' => 0.002, 'theta' => -8.1, 'vega' => 12.3 } }
        }
      }

      service = described_class.new(index_key: 'NIFTY')
      result = service.send(:merge_chain_data, legs, api_chain)

      expect(result.first).to include(oi: 50_000, iv: 14.2, delta: 0.52, gamma: 0.002, theta: -8.1, vega: 12.3)
    end

    it 'leaves legs unchanged when api_chain is nil' do
      legs = [{ strike: 24800.0, type: 'CE', iv: nil, oi: nil }]

      service = described_class.new(index_key: 'NIFTY')
      result = service.send(:merge_chain_data, legs, nil)

      expect(result).to eq(legs)
    end
  end

  describe '#resubscribe_legs! (position-aware unsubscribe)' do
    let(:service) { described_class.new(index_key: 'NIFTY') }

    before do
      # Seed @subscribed_legs as if both legs were already subscribed from a
      # prior cycle, then feed a new ATM window that drops both of them.
      service.instance_variable_set(:@subscribed_legs, [
                                      { segment: 'NSE_FNO', security_id: '24700CE' },
                                      { segment: 'NSE_FNO', security_id: '24900PE' }
                                    ])
      allow(Live::PositionIndex.instance).to receive(:trackers_for).with('24700CE')
                                                                   .and_return([{ id: 1, security_id: '24700CE' }])
      allow(Live::PositionIndex.instance).to receive(:trackers_for).with('24900PE').and_return([])
    end

    it 'does not unsubscribe a leg with an active position tracker' do
      expect(Live::MarketFeedHub.instance).not_to receive(:unsubscribe).with(segment: 'NSE_FNO', security_id: '24700CE')

      service.send(:resubscribe_legs!, [])
    end

    it 'unsubscribes a leg without an active position via the singular #unsubscribe method' do
      expect(Live::MarketFeedHub.instance).to receive(:unsubscribe).with(segment: 'NSE_FNO', security_id: '24900PE')
      expect(Live::MarketFeedHub.instance).not_to receive(:unsubscribe_many)

      service.send(:resubscribe_legs!, [])
    end

    it 'keeps the position-protected leg tracked as subscribed for future cycles' do
      service.send(:resubscribe_legs!, [])

      expect(service.instance_variable_get(:@subscribed_legs)).to include(segment: 'NSE_FNO', security_id: '24700CE')
    end
  end

  describe '#unsubscribe_current_legs! (position-aware, called from #stop!)' do
    let(:service) { described_class.new(index_key: 'NIFTY') }

    before do
      service.instance_variable_set(:@subscribed_legs, [
                                      { segment: 'NSE_FNO', security_id: '24700CE' },
                                      { segment: 'NSE_FNO', security_id: '24900PE' }
                                    ])
      allow(Live::PositionIndex.instance).to receive(:trackers_for).with('24700CE')
                                                                   .and_return([{ id: 1, security_id: '24700CE' }])
      allow(Live::PositionIndex.instance).to receive(:trackers_for).with('24900PE').and_return([])
    end

    it 'leaves the position-protected leg subscribed and unsubscribes only the free leg' do
      expect(Live::MarketFeedHub.instance).not_to receive(:unsubscribe).with(segment: 'NSE_FNO', security_id: '24700CE')
      expect(Live::MarketFeedHub.instance).to receive(:unsubscribe).with(segment: 'NSE_FNO', security_id: '24900PE')

      service.send(:unsubscribe_current_legs!)

      expect(service.instance_variable_get(:@subscribed_legs)).to eq([{ segment: 'NSE_FNO', security_id: '24700CE' }])
    end
  end

  describe 'REST poll staggering' do
    it 'assigns different initial last_poll_at offsets to different index_keys' do
      nifty_service = described_class.new(index_key: 'NIFTY')

      banknifty_cfg = { key: 'BANKNIFTY', segment: 'IDX_I', sid: '25' }
      allow(IndexConfigLoader).to receive(:load_indices).and_return([banknifty_cfg])
      banknifty_service = described_class.new(index_key: 'BANKNIFTY')

      now = Time.zone.local(2026, 7, 5, 9, 30, 0)
      allow(Time).to receive(:current).and_return(now)

      nifty_offset = nifty_service.send(:initial_last_poll_at)
      banknifty_offset = banknifty_service.send(:initial_last_poll_at)

      expect(nifty_offset).not_to eq(banknifty_offset)
      expect(banknifty_offset - nifty_offset).to be_within(0.001).of(
        Options::ChainWatchService::POLL_INTERVAL_SECONDS / 3.0
      )
    end

    it 'defaults unknown index_keys to ordinal 0 without raising' do
      unknown_cfg = { key: 'FOO', segment: 'IDX_I', sid: '99' }
      allow(IndexConfigLoader).to receive(:load_indices).and_return([unknown_cfg])
      service = described_class.new(index_key: 'FOO')

      expect { service.send(:initial_last_poll_at) }.not_to raise_error
    end
  end

  describe '#start! and #stop!' do
    let(:analyzer) { instance_double(Options::DerivativeChainAnalyzer) }

    before do
      allow(Options::DerivativeChainAnalyzer).to receive(:new).and_return(analyzer)
      allow(analyzer).to receive_messages(
        spot_ltp: 24800.0, find_nearest_expiry: '2026-07-10', fetch_api_chain: {}
      )
      allow(ActionCable.server).to receive(:broadcast)
    end

    it 'is not running before start! and running after' do
      service = described_class.new(index_key: 'NIFTY')
      expect(service.running?).to be(false)

      service.start!
      expect(service.running?).to be(true)

      service.stop!
      expect(service.running?).to be(false)
    end

    it 'is idempotent — calling start! twice does not raise' do
      service = described_class.new(index_key: 'NIFTY')
      service.start!
      expect { service.start! }.not_to raise_error
      service.stop!
    end

    it 'subscribes resolved legs on MarketFeedHub when starting' do
      # NOTE: DatabaseCleaner runs specs inside a per-test transaction (see
      # spec/support/database_cleaner.rb). Rows created on the test's DB connection are
      # invisible to the background thread's own connection, so real Derivative rows
      # can never be observed cross-thread here. Stub #resolve_atm_legs (already covered
      # by its own examples above) to hand the loop a canned leg list instead, keeping
      # this example deterministic and focused on the subscribe wiring.
      service = described_class.new(index_key: 'NIFTY')
      fake_legs = [{ strike: 24800.0, type: 'CE', security_id: '24800CE', segment: 'NSE_FNO', lot_size: 50 }]
      allow(service).to receive(:resolve_atm_legs).and_return(fake_legs)

      subscribed = Queue.new
      allow(Live::MarketFeedHub.instance).to receive(:subscribe_many) do |legs|
        subscribed << legs
        []
      end

      service.start!
      result = begin
        Timeout.timeout(2) { subscribed.pop }
      rescue Timeout::Error
        nil
      end
      service.stop!

      expect(result).to eq([{ segment: 'NSE_FNO', security_id: '24800CE' }])
    end
  end
end
