# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Reports::MarketBrief::LiveBrief do
  subject(:live) { described_class.call(mode: :paper) }

  before do
    travel_to(brief_market_open_time)
    stub_market_brief_sources
  end

  def analysed_report(at:, decision: 'NO_TRADE')
    snapshot = Reports::MarketBrief::SnapshotBuilder.call
    snapshot['setup']['decision'] = decision
    report, = MarketBriefReport.request!(mode: :paper, now: at)
    report.update!(status: 'ready', snapshot: snapshot, snapshot_digest: Reports::MarketBrief::SnapshotBuilder.digest(snapshot),
                   snapshot_generated_at: at, ai_status: 'completed', ai_model: 'ollama:test',
                   ai_analysis: { 'executive_summary' => 'Grounded.' }, ai_generated_at: at)
    report
  end

  it 'serves current deterministic facts without ever calling the LLM' do
    expect(Services::Ai::OllamaClient).not_to receive(:instance)
    expect(live).to include(live: true, mode: 'paper')
    expect(live[:snapshot].dig('setup', 'decision')).to eq('NO_TRADE')
    expect(live[:snapshot]['indices'].first.dig('quote', 'status')).to eq('live')
  end

  it 'reports AI as unavailable when nothing has been analysed today' do
    expect(live[:ai]).to include(status: 'unavailable', analysis: nil, error: 'no_analysis_generated_today')
  end

  it 'attaches the latest validated commentary with its age and basis' do
    report = analysed_report(at: 5.minutes.ago)
    expect(live[:ai]).to include(status: 'completed', report_id: report.id, age_seconds: 300, stale: false,
                                 decision_changed: false, analysis: { 'executive_summary' => 'Grounded.' })
  end

  it 'flags commentary as stale and the decision as changed instead of hiding the conflict' do
    analysed_report(at: 30.minutes.ago, decision: 'QUALIFIED')
    expect(live[:ai]).to include(stale: true, decision_changed: true, decision_at_analysis: 'QUALIFIED')
    expect(live[:snapshot].dig('setup', 'decision')).to eq('NO_TRADE')
  end

  it 'surfaces a newer failed attempt alongside older valid commentary' do
    analysed_report(at: 10.minutes.ago)
    failed, = MarketBriefReport.request!(mode: :paper)
    failed.update!(status: 'ready', snapshot: { 'x' => 1 }, ai_status: 'invalid', ai_error: 'unparseable_json')

    expect(live[:ai][:status]).to eq('completed')
    expect(live[:ai][:latest_attempt]).to include(report_id: failed.id, status: 'invalid', error: 'unparseable_json')
  end

  it 'ignores commentary from a previous trading day' do
    analysed_report(at: 1.day.ago)
    expect(live[:ai]).to include(status: 'unavailable', analysis: nil, latest_attempt: nil)
  end

  it 'builds uncached when the cache store fails' do
    allow(Rails.cache).to receive(:fetch).and_raise(Redis::CannotConnectError)
    expect(live[:snapshot]['schema_version']).to eq(1)
  end

  it 'does not create reports, positions or orders' do
    expect { live }.not_to(change { [MarketBriefReport.count, PositionTracker.count] })
  end
end
