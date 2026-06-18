# frozen_string_literal: true

require 'rails_helper'

RSpec.describe OptionsBuying::StreamWriter do
  let(:ts) { 1_700_000_123 }
  let(:tick) { { security_id: 'opt1', ltp: 120.5, oi: 4500, volume: 9000, ts: ts } }

  before do
    allow(OptionsBuying::Mode).to receive_messages(streams_enabled?: true, config: {})
    allow(OptionsBuying::StateStore).to receive(:xadd_tick)
    allow(OptionsBuying::StateStore).to receive(:cache_tick_snapshot)
    allow(OptionsBuying::StateStore).to receive(:track_monitored_strike)
    allow(OptionsBuying::StateStore).to receive(:append_minute_tick)
  end

  it 'returns nil and writes nothing when streams are disabled' do
    allow(OptionsBuying::Mode).to receive(:streams_enabled?).and_return(false)
    expect(described_class.record!(tick)).to be_nil
    expect(OptionsBuying::StateStore).not_to have_received(:xadd_tick)
  end

  it 'returns nil for a blank security_id or non-positive ltp' do
    expect(described_class.record!(tick.merge(security_id: ''))).to be_nil
    expect(described_class.record!(tick.merge(ltp: 0))).to be_nil
  end

  it 'appends to the stream, caches the snapshot, and tracks the strike' do
    result = described_class.record!(tick)

    expect(result).to include(ltp: 120.5, oi: 4500, volume: 9000, ts: ts, bucket: ts - (ts % 60))
    expect(OptionsBuying::StateStore).to have_received(:xadd_tick).with('opt1', hash_including(ltp: 120.5))
    expect(OptionsBuying::StateStore).to have_received(:cache_tick_snapshot).with('opt1', hash_including(volume: 9000))
    expect(OptionsBuying::StateStore).to have_received(:track_monitored_strike).with('opt1')
  end

  it 'also writes the legacy minute bucket by default' do
    described_class.record!(tick)
    expect(OptionsBuying::StateStore).to have_received(:append_minute_tick).with('opt1', ts - (ts % 60), anything)
  end

  it 'skips the legacy minute bucket when legacy_zset_enabled is false' do
    allow(OptionsBuying::Mode).to receive(:config).and_return(streams: { legacy_zset_enabled: false })
    described_class.record!(tick)
    expect(OptionsBuying::StateStore).not_to have_received(:append_minute_tick)
  end

  it 'swallows StateStore errors and returns nil' do
    allow(OptionsBuying::StateStore).to receive(:xadd_tick).and_raise(StandardError, 'boom')
    expect(described_class.record!(tick)).to be_nil
  end
end
