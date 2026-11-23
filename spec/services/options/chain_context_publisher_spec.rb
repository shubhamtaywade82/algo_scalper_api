# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Options::ChainContextPublisher do
  let(:redis) { instance_double(Redis) }
  let(:publisher) { described_class.new(index_key: 'NIFTY', redis: redis) }
  let(:legs) do
    [
      { strike: 25_400.0, type: 'CE', security_id: 'a', segment: 'NSE_FNO', lot_size: 75,
        ltp: 100.0, oi: 200_000, oi_change: 0, volume: 1_000, bid: nil, ask: nil, feed_stale: false },
      { strike: 25_400.0, type: 'PE', security_id: 'b', segment: 'NSE_FNO', lot_size: 75,
        ltp: 100.0, oi: 300_000, oi_change: 0, volume: 1_000, bid: nil, ask: nil, feed_stale: false },
      { strike: 25_500.0, type: 'CE', security_id: 'c', segment: 'NSE_FNO', lot_size: 75,
        ltp: 100.0, oi: 900_000, oi_change: 0, volume: 1_000, bid: nil, ask: nil, feed_stale: false },
      { strike: 25_500.0, type: 'PE', security_id: 'd', segment: 'NSE_FNO', lot_size: 75,
        ltp: 100.0, oi: 1_200_000, oi_change: 0, volume: 1_000, bid: nil, ask: nil, feed_stale: false }
    ]
  end
  let(:snapshot) do
    { index_key: 'NIFTY', spot: 25_455.0, atm_strike: 25_500.0, expiry: '2026-11-26',
      legs: legs, chain_stale: false, updated_at: Time.current.iso8601 }
  end

  describe '#publish' do
    it 'writes the chain-context/1 payload under dhan:chain:context:NIFTY with a 15s TTL' do
      expect(redis).to receive(:set).with(
        'dhan:chain:context:NIFTY',
        kind_of(String),
        { ex: described_class::TTL_SECONDS }
      ) do |_key, json, _opts|
        payload = JSON.parse(json)
        expect(payload['schema']).to eq('chain-context/1')
        # call_oi 1.1m, put_oi 1.5m -> pcr 1.36 (round2); both strikes within
        # 3*50 of ATM 25_500 -> atm band = window
        expect(payload['pcr']).to eq(1.36)
        expect(payload['headroom_ce']).to eq(45.0)
        expect(payload['headroom_pe']).to eq(-45.0)
        expect(payload['sentiment_score']).to eq(25)
        expect(payload['bias']).to eq('BULLISH')
      end
      expect(publisher.publish(snapshot)).to be(true)
    end

    it 'returns false without writing when the snapshot is unpublishable (stale chain)' do
      expect(redis).not_to receive(:set)
      expect(publisher.publish(snapshot.merge(chain_stale: true))).to be(false)
    end

    it 'returns false and does not raise when Redis is down' do
      allow(redis).to receive(:set).and_raise(Redis::ConnectionError.new('down'))
      expect(publisher.publish(snapshot)).to be(false)
    end
  end

  describe '#fetch' do
    it 'round-trips the payload through JSON' do
      stored = nil
      allow(redis).to receive(:set) { |_k, json, _o|
        stored = json
        'OK'
      }
      allow(redis).to receive(:get) { stored }

      publisher.publish(snapshot)
      payload = publisher.fetch

      expect(payload['schema']).to eq('chain-context/1')
      expect(payload['headroom_ce']).to eq(45.0)
      expect(payload['bias']).to eq('BULLISH')
    end

    it 'returns nil for a missing key' do
      allow(redis).to receive(:get).and_return(nil)
      expect(publisher.fetch).to be_nil
    end
  end

  describe 'integration with ChainWatchService' do
    it 'ChainWatchService publishes the context snapshot on each broadcast cycle' do
      publisher = described_class.new(index_key: 'NIFTY', redis: redis)
      allow(redis).to receive(:set)
      service = Options::ChainWatchService.new(index_key: 'NIFTY', chain_context_publisher: publisher)

      allow(service).to receive(:resolve_atm_legs).and_return(legs)
      allow(service).to receive(:resubscribe_legs!)
      allow(Live::TickQuery).to receive(:for_security).and_return(nil)
      allow(Options::DerivativeChainAnalyzer).to receive(:new).and_return(
        instance_double(Options::DerivativeChainAnalyzer,
                        spot_ltp: 25_455.0,
                        find_nearest_expiry: '2026-11-26',
                        fetch_api_chain: {})
      )
      allow(ActionCable.server).to receive(:broadcast)

      # Run one cycle of the loop in a caller thread with sleep stubbed,
      # then stop: publish must have fired before the broadcast. The spec
      # thread drives run_loop directly (no start!), so running? must yield
      # true once then false - exactly one cycle - for publish to fire.
      allow(service).to receive(:running?).and_return(true, false)
      allow(service).to receive(:sleep)
      th = Thread.new { service.send(:run_loop) }
      Timeout.timeout(5) { Thread.pass until th.status == 'sleep' || !th.status }
      service.stop!
      th.kill rescue nil

      expect(redis).to have_received(:set).with('dhan:chain:context:NIFTY', kind_of(String), { ex: 15 })
    end
  end
end
