# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DataQuality::TickStalenessSamplerJob do
  # Real cache store: test env's Rails.cache is a NullStore (writes "succeed" but nothing
  # is ever readable), same reason placer_spec.rb swaps in a real MemoryStore for its
  # claim! tests.
  let(:real_cache) { ActiveSupport::Cache::MemoryStore.new }
  let(:keys) { described_class.cache_keys_for(Date.current) }

  before { allow(Rails).to receive(:cache).and_return(real_cache) }

  it 'increments total every run, and stale only when the ticks feed is stale' do
    allow(Live::FeedHealthService.instance).to receive(:stale?).with(:ticks).and_return(true)

    described_class.new.perform

    expect(real_cache.read(keys[:total])).to eq(1)
    expect(real_cache.read(keys[:stale])).to eq(1)
  end

  it 'does not increment the stale counter when the feed is healthy' do
    allow(Live::FeedHealthService.instance).to receive(:stale?).with(:ticks).and_return(false)

    described_class.new.perform

    expect(real_cache.read(keys[:total])).to eq(1)
    expect(real_cache.read(keys[:stale])).to be_nil
  end

  it 'accumulates across multiple runs' do
    allow(Live::FeedHealthService.instance).to receive(:stale?).with(:ticks).and_return(true, false, true)

    3.times { described_class.new.perform }

    expect(real_cache.read(keys[:total])).to eq(3)
    expect(real_cache.read(keys[:stale])).to eq(2)
  end
end
