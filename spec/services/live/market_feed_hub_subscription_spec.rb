# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Live::MarketFeedHub do
  let(:hub) { described_class.instance }
  let(:ws_client) { instance_double(DhanHQ::WS::Client, subscribe_one: true, unsubscribe_one: true) }

  before do
    hub.stop!
    hub.instance_variable_set(:@running, true)
    hub.instance_variable_set(:@ws_client, ws_client)
    hub.instance_variable_set(:@subscribed_keys, Concurrent::Set.new)
    hub.instance_variable_set(:@watchlist, [{ segment: 'IDX_I', security_id: '13' }])
    hub.send(:refresh_watchlist_keys!)
    allow(hub).to receive(:ensure_running!).and_return(true)
  end

  after do
    hub.stop!
  end

  it 'subscribes option contracts only once and dedupes future calls' do
    expect(ws_client).to receive(:subscribe_one).once.with(segment: 'NSE_FNO', security_id: '12345')

    hub.subscribe_instrument(segment: 'NSE_FNO', security_id: '12345')
    hub.subscribe_instrument(segment: 'NSE_FNO', security_id: '12345')
  end

  it 'does not unsubscribe watchlist instruments' do
    hub.instance_variable_get(:@subscribed_keys).add('IDX_I:13')
    expect(ws_client).not_to receive(:unsubscribe_one)

    hub.unsubscribe_instrument(segment: 'IDX_I', security_id: '13')
  end

  it 'unsubscribes option contracts that are not watchlist instruments' do
    hub.instance_variable_get(:@subscribed_keys).add('NSE_FNO:99999')
    expect(ws_client).to receive(:unsubscribe_one).once.with(segment: 'NSE_FNO', security_id: '99999')

    hub.unsubscribe_instrument(segment: 'NSE_FNO', security_id: '99999')
  end
end
