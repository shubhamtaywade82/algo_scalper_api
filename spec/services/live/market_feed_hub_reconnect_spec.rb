# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Live::MarketFeedHub do
  describe '#handle_reconnect' do
    it 'resubscribes active positions immediately on a gem-reported reconnect' do
      hub = described_class.instance
      allow(hub).to receive(:resubscribe_active_positions_after_reconnect)

      hub.send(:handle_reconnect, { attempt: 2, resubscribed: false })

      expect(hub).to have_received(:resubscribe_active_positions_after_reconnect)
    end
  end

  describe '#restart!' do
    let(:hub) { described_class.instance }

    before do
      allow(hub).to receive(:running?).and_return(true)
      allow(hub).to receive(:stop!)
      allow(hub).to receive(:start!)
      allow(hub).to receive(:sleep)
      hub.instance_variable_set(:@reconnect_attempts, 0)
      hub.instance_variable_set(:@restarting, false)
    end

    it 'applies exponential backoff on consecutive restart calls' do
      hub.send(:restart!)
      expect(hub).to have_received(:sleep).with(2)

      hub.send(:restart!)
      expect(hub).to have_received(:sleep).with(4)

      hub.send(:restart!)
      expect(hub).to have_received(:sleep).with(8)
    end

    it 'resets reconnect attempts when update_connection_state! is called' do
      hub.send(:restart!)
      hub.send(:update_connection_state!)
      expect(hub.instance_variable_get(:@reconnect_attempts)).to eq(0)
    end
  end

  describe '#restart! subscription and callback preservation' do
    let(:hub) { described_class.instance }
    let(:ws_client_initial) { instance_double(DhanHQ::WS::Client, on: true, start: true, disconnect!: true, subscribe_many: true) }
    let(:ws_client_restarted) { instance_double(DhanHQ::WS::Client, on: true, start: true, disconnect!: true, subscribe_many: true) }

    before do
      hub.stop!
      allow(hub).to receive(:sleep)
      allow(hub).to receive(:start_watchdog!)
      allow(hub).to receive(:subscribe_watchlist)
      allow(hub).to receive_messages(enabled?: true, load_watchlist: [])
      allow(hub).to receive(:build_client).and_return(ws_client_initial, ws_client_restarted)
      allow(Live::TickCache).to receive(:put)
      allow(Live::FeedHealthService.instance).to receive(:mark_success!)
      allow(Live::SystemStatusCache.instance).to receive(:report_heartbeat)
      allow(Live::PositionIndex.instance).to receive(:trackers_for).and_return([])
      hub.instance_variable_set(:@reconnect_attempts, 0)
      hub.instance_variable_set(:@restarting, false)
    end

    after { hub.stop! }

    it 're-subscribes non-watchlist instruments and retains tick callbacks across restart!' do
      received = []
      hub.start!
      hub.subscribe_many([{ segment: 'NSE_FNO', security_id: '47812' }])
      hub.on_tick { |tick| received << tick[:security_id] }

      hub.send(:restart!)
      hub.send(:handle_tick, { segment: 'NSE_FNO', security_id: '47812', ltp: 239.0, kind: :ticker })

      expect(hub.subscribed?(segment: 'NSE_FNO', security_id: '47812')).to be(true)
      expect(ws_client_restarted).to have_received(:subscribe_many).with([{ ExchangeSegment: 'NSE_FNO', SecurityId: '47812' }])
      expect(received).to eq(['47812'])
    end
  end
end
