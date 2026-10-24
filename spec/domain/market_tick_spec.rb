# frozen_string_literal: true

require 'rails_helper'

RSpec.describe MarketTick do
  def tick(timestamp:, ltp: 100.0)
    described_class.new(
      segment: 'NSE_FNO', security_id: '60001', ltp: ltp,
      timestamp: timestamp, oi: 0, oi_change: 0, bid: 99.9, ask: 100.1,
      volume: 10, prev_close: 99.5
    )
  end

  describe '#freshness (tri-state contract)' do
    it 'returns :fresh for a recent tick' do
      expect(tick(timestamp: 1.second.ago).freshness).to eq(:fresh)
    end

    it 'returns :stale for an old-but-parseable tick' do
      expect(tick(timestamp: 10.minutes.ago).freshness).to eq(:stale)
    end

    it 'returns :invalid for a missing timestamp' do
      expect(tick(timestamp: nil).freshness).to eq(:invalid)
    end

    it 'returns :invalid for an unparseable timestamp' do
      expect(tick(timestamp: 'not-a-time').freshness).to eq(:invalid)
    end

    it 'honours a custom max-age window' do
      expect(tick(timestamp: 10.seconds.ago).freshness(30)).to eq(:fresh)
      expect(tick(timestamp: 10.seconds.ago).freshness(5)).to eq(:stale)
    end
  end

  describe '#fresh? compatibility' do
    it 'is true only for fresh ticks' do
      expect(tick(timestamp: 1.second.ago)).to be_fresh
    end

    it 'is false for stale ticks' do
      expect(tick(timestamp: 10.minutes.ago)).not_to be_fresh
    end

    it 'is false (not raise) for malformed timestamps — but #invalid? distinguishes them' do
      malformed = tick(timestamp: 'garbage')
      expect(malformed).not_to be_fresh
      expect(malformed).to be_invalid
      expect(tick(timestamp: 10.minutes.ago)).not_to be_invalid
    end
  end

  describe '#stale? / #invalid?' do
    it 'classifies parseable-old vs unparseable ticks distinctly' do
      expect(tick(timestamp: 10.minutes.ago)).to be_stale
      expect(tick(timestamp: nil)).to be_invalid
      expect(tick(timestamp: 1.second.ago)).not_to be_stale
    end
  end
end
