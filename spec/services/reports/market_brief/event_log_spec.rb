# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Reports::MarketBrief::EventLog do
  let(:memory_cache) { ActiveSupport::Cache::MemoryStore.new }
  let(:today) { Time.find_zone('Asia/Kolkata').local(2026, 10, 27, 11, 0, 0) }

  before do
    allow(Rails).to receive(:cache).and_return(memory_cache)
    travel_to(today)
  end

  def event_at(time, kind: 'level_crossed')
    { 'kind' => kind, 'at' => time.iso8601 }
  end

  it 'returns today\'s events oldest first' do
    described_class.append('paper', [event_at(today - 5.minutes)])
    described_class.append('paper', [event_at(today - 1.minute, kind: 'regime_changed')])

    expect(described_class.recent('paper').pluck('kind')).to eq(%w[level_crossed regime_changed])
  end

  it 'drops events from a previous trading date' do
    described_class.append('paper', [event_at(today - 1.day, kind: 'old')])

    expect(described_class.recent('paper')).to be_empty
  end

  it 'keeps only the most recent entries' do
    described_class.append('paper', Array.new(60) { |i| event_at(today - i.minutes, kind: "k#{i}") })

    expect(described_class.recent('paper').size).to eq(described_class::CAP)
  end

  it 'keeps modes apart' do
    described_class.append('live', [event_at(today, kind: 'live_only')])

    expect(described_class.recent('paper')).to be_empty
  end
end
