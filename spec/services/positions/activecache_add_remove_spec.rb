# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Positions::ActiveCache do
  subject(:cache) { described_class.instance }

  let(:tracker) do
    instance_double(
      PositionTracker,
      id: 42,
      active?: true,
      entry_price: BigDecimal(100),
      segment: 'NSE_FNO',
      security_id: '12345',
      quantity: 50,
      high_water_mark_pnl: 0,
      breakeven_locked?: false,
      trailing_stop_price: nil,
      created_at: Time.current
    )
  end

  let(:hub) { instance_double(Live::MarketFeedHub, subscribe_instrument: true, unsubscribe_instrument: true) }
  let(:feature_flags) { { feature_flags: { enable_auto_subscribe_unsubscribe: true } } }

  before do
    cache.clear
    allow(Live::MarketFeedHub).to receive(:instance).and_return(hub)
    allow(AlgoConfig).to receive(:fetch).and_return(feature_flags)
    allow(Live::TickCache).to receive(:ltp).and_return(nil)
  end

  after do
    cache.clear
  end

  it 'subscribes option instruments and emits notifications when adding a position' do
    added_payloads = []
    subscriber = ActiveSupport::Notifications.subscribe('positions.added') do |_name, _start, _finish, _id, payload|
      added_payloads << payload
    end

    cache.add_position(tracker: tracker)

    expect(hub).to have_received(:subscribe_instrument).with(segment: 'NSE_FNO', security_id: '12345')
    expect(added_payloads).to include(hash_including(tracker_id: 42))
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
  end

  it 'unsubscribes option instruments and emits notifications when removing a position' do
    cache.add_position(tracker: tracker)
    allow(hub).to receive(:unsubscribe_instrument).and_return(true)

    removed_payloads = []
    subscriber = ActiveSupport::Notifications.subscribe('positions.removed') do |_name, _start, _finish, _id, payload|
      removed_payloads << payload
    end

    cache.remove_position(tracker.id)

    expect(hub).to have_received(:unsubscribe_instrument).with(segment: 'NSE_FNO', security_id: '12345')
    expect(removed_payloads).to include(hash_including(tracker_id: 42))
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
  end
end
