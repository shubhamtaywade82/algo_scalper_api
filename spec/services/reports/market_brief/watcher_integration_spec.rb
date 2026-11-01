# frozen_string_literal: true

require 'rails_helper'

# Drives the real SnapshotBuilder (cached sources stubbed) through the watcher, so a
# key-name mismatch between the snapshot and the detector cannot pass unit specs unnoticed.
RSpec.describe Reports::MarketBrief::Watcher do # rubocop:disable RSpec/DescribeMethod, RSpec/SpecFilePathFormat -- exercises the watcher end to end
  let(:open_at) { Time.find_zone('Asia/Kolkata').local(2026, 10, 27, 10, 30, 0) }
  let(:price) { { ltp: 24_500.5 } }
  let(:broadcaster) { class_double(Reports::MarketBrief::Broadcaster, events: nil, report: nil) }
  let(:watcher) { described_class.new(broadcaster: broadcaster) }

  before do
    travel_to(open_at)
    stub_market_brief_sources
    allow(Live::TickQuery).to receive(:for_security) do |segment:, security_id:|
      next nil unless segment == 'IDX_I'

      brief_tick(ltp: price[:ltp], prev_close: 24_400.0, at: Time.current, security_id: security_id)
    end
    allow(AlgoConfig).to receive(:mode).and_return(:paper)
    allow(Services::Ai::OllamaClient.instance).to receive(:enabled?).and_return(true)
    allow(Ai::GenerativeAiMarketGate).to receive(:skip?).and_return(false)
    allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new)
  end

  it 'announces the open, then turns a swing-high cross into one AI run carrying the level' do
    frames = []
    allow(broadcaster).to receive(:events) { |**kw| frames << kw }
    watcher.cycle
    MarketBriefReport.last.update!(status: 'ready', ai_status: 'completed', created_at: open_at - 2.hours)

    travel_to(open_at + 10.seconds)
    price[:ltp] = 24_540.0 # decided above the 24,520 swing high, beyond its 0.05% band (≈ 24,532)
    result = nil
    expect { result = watcher.cycle }.to have_enqueued_job(Reports::MarketBriefJob).with(kind_of(Integer), 'event', false)

    report = MarketBriefReport.find(result[:report_id])
    expect(report.trigger_reasons).to include(a_string_matching(/NIFTY .* swing high 24520\.00 upward/))
    crossing = frames.last
    expect(crossing[:events]).to include(hash_including('kind' => 'level_crossed', 'direction' => 'upward'))
    expect(crossing[:snapshot].dig('indices', 0, 'quote', 'ltp')).to eq(24_540.0)
  end

  it 'stays quiet while price chops inside the band around the swing high' do
    watcher.cycle
    MarketBriefReport.last.update!(status: 'ready', ai_status: 'completed', created_at: open_at - 2.hours)

    [24_510.0, 24_515.0, 24_508.0].each_with_index do |ltp, i|
      travel_to(open_at + (i + 1).minutes)
      price[:ltp] = ltp
      expect { watcher.cycle }.not_to have_enqueued_job(Reports::MarketBriefJob)
    end
  end
end
