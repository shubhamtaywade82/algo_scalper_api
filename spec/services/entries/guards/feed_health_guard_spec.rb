# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Entries::Guards::FeedHealthGuard do
  describe '.call' do
    let(:context) { {} }
    let(:service) { instance_double(Live::FeedHealthService) }

    before do
      allow(Live::FeedHealthService).to receive(:instance).and_return(service)
    end

    context 'when in paper trading mode' do
      let(:context) { { paper_trading: true } }

      it 'allows entry when paper required feeds (:ticks) are healthy' do
        allow(service).to receive(:assert_healthy!).with(described_class::PAPER_REQUIRED_FEEDS).and_return(true)

        result = described_class.call(context)

        expect(result).to eq(Entries::EntryGuardPipeline::PASS)
      end
    end

    context 'when in live trading mode' do
      let(:context) { { paper_trading: false } }

      it 'allows entry when all required feeds (:ticks, :positions) are healthy' do
        allow(service).to receive(:assert_healthy!).with(described_class::REQUIRED_FEEDS).and_return(true)

        result = described_class.call(context)

        expect(result).to eq(Entries::EntryGuardPipeline::PASS)
      end
    end

    context 'when a feed is stale' do
      it 'blocks entry with the feed name and staleness detail' do
        allow(service).to receive(:assert_healthy!).and_raise(
          Live::FeedHealthService::FeedStaleError.new(feed: :ticks, last_seen_at: 15.seconds.ago, threshold: 10)
        )

        result = described_class.call(context)

        expect(result).to include(blocked: a_string_matching(/feed_stale/))
        expect(result[:blocked]).to include('ticks')
      end
    end

    context 'when on cold start before any feed has ever synced' do
      it 'blocks entry (no timestamp yet means unknown health, not healthy)' do
        allow(service).to receive(:assert_healthy!).and_raise(
          Live::FeedHealthService::FeedStaleError.new(feed: :positions, last_seen_at: nil, threshold: 30)
        )

        result = described_class.call(context)

        expect(result).to include(blocked: a_string_matching(/feed_stale/))
        expect(result[:blocked]).to include('positions')
      end
    end
  end
end
