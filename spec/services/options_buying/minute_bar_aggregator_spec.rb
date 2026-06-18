# frozen_string_literal: true

require 'rails_helper'

RSpec.describe OptionsBuying::MinuteBarAggregator do
  before do
    allow(OptionsBuying::StateStore).to receive(:append_minute_tick)
    allow(OptionsBuying::BreakoutEvaluator).to receive(:evaluate!)
    allow(IndexConfigLoader).to receive(:load_indices).and_return([{ key: 'NIFTY' }])
    allow(OptionsBuying::StateStore).to receive(:radar_strikes).with('NIFTY').and_return(
      [{ security_id: 'opt1' }]
    )
  end

  it 'ignores ticks with a blank security_id or non-positive ltp' do
    described_class.record_tick!({ security_id: '', ltp: 100.0, ts: 1 })
    described_class.record_tick!({ security_id: 'opt1', ltp: 0, ts: 1 })
    expect(OptionsBuying::StateStore).not_to have_received(:append_minute_tick)
  end

  it 'appends the tick into its 60s bucket' do
    ts = 1_700_000_130 # %60 = 30 (mid-minute)
    described_class.record_tick!({ security_id: 'opt1', ltp: 120.0, oi: 4500, volume: 9000, ts: ts })
    expect(OptionsBuying::StateStore).to have_received(:append_minute_tick).with(
      'opt1', ts - (ts % 60), hash_including(ltp: 120.0, oi: 4500, vol: 9000)
    )
  end

  it 'evaluates the just-completed bucket near the end of the minute' do
    ts = 1_700_000_159 # %60 = 59 (>= 55)
    described_class.record_tick!({ security_id: 'opt1', ltp: 120.0, ts: ts })
    expect(OptionsBuying::BreakoutEvaluator).to have_received(:evaluate!).with(
      index_key: 'NIFTY', security_id: 'opt1', bucket: (ts - (ts % 60)) - 60
    )
  end

  it 'does not evaluate mid-minute' do
    described_class.record_tick!({ security_id: 'opt1', ltp: 120.0, ts: 1_700_000_130 })
    expect(OptionsBuying::BreakoutEvaluator).not_to have_received(:evaluate!)
  end
end
