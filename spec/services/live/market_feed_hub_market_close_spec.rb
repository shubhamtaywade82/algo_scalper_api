# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Live::MarketFeedHub do
  let(:hub) { described_class.instance }
  let(:tracker) do
    instance_double(
      PositionTracker,
      id: 1,
      security_id: '12345',
      segment: 'NSE_FNO',
      watchable: nil,
      instrument: instance_double(Instrument, exchange_segment: 'NSE_FNO')
    )
  end

  describe '#resubscribe_active_positions_after_reconnect' do
    before do
      allow(hub).to receive_messages(running?: true, load_watchlist: [
                                       { segment: 'IDX_I', security_id: '13' }
                                     ])
      allow(hub).to receive(:subscribe_many)
      allow(PositionTracker).to receive_message_chain(:active, :includes, :to_a).and_return([tracker])
      allow(hub).to receive(:subscribe)
    end

    context 'when market is closed' do
      before do
        allow(TradingSession::Service).to receive(:market_closed?).and_return(true)
      end

      it 'resubscribes watchlist items' do
        hub.send(:resubscribe_active_positions_after_reconnect)
        expect(hub).to have_received(:subscribe_many).with(anything)
      end

      it 'does not resubscribe active positions' do
        hub.send(:resubscribe_active_positions_after_reconnect)
        expect(hub).not_to have_received(:subscribe)
      end
    end

    context 'when market is open' do
      before do
        allow(TradingSession::Service).to receive(:market_closed?).and_return(false)
      end

      it 'resubscribes both watchlist items and active positions' do
        hub.send(:resubscribe_active_positions_after_reconnect)
        expect(hub).to have_received(:subscribe_many).with(anything)
        expect(hub).to have_received(:subscribe).at_least(:once)
      end
    end
  end
end
