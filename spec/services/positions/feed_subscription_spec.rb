# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Positions::FeedSubscription do
  describe '.segment_key_for' do
    it 'prefers tracker segment' do
      tracker = instance_double(PositionTracker, segment: 'NSE_FNO', watchable: nil, instrument: nil)

      expect(described_class.segment_key_for(tracker: tracker)).to eq('NSE_FNO')
    end
  end

  describe '.call' do
    it 'subscribes through market feed hub' do
      hub = instance_double(Live::MarketFeedHub, running?: true, subscribe: true)
      allow(Live::MarketFeedHub).to receive(:instance).and_return(hub)

      tracker = instance_double(
        PositionTracker,
        segment: 'NSE_FNO',
        watchable: nil,
        instrument: nil,
        security_id: '12345'
      )

      described_class.call(tracker: tracker)

      expect(hub).to have_received(:subscribe).with(segment: 'NSE_FNO', security_id: '12345')
    end
  end

  describe '.unsubscribe' do
    it 'skips IDX_I unsubscription' do
      hub = instance_double(Live::MarketFeedHub, running?: true, unsubscribe: true)
      allow(Live::MarketFeedHub).to receive(:instance).and_return(hub)

      tracker = instance_double(
        PositionTracker,
        segment: 'IDX_I',
        watchable: nil,
        instrument: nil,
        security_id: '13'
      )

      described_class.unsubscribe(tracker: tracker)

      expect(hub).not_to have_received(:unsubscribe)
    end
  end
end
