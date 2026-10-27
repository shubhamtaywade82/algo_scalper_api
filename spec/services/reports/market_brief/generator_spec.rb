# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Reports::MarketBrief::Generator do
  let(:report) { MarketBriefReport.request!(mode: :paper).first }
  let(:client) { instance_double(Services::Ai::OllamaClient, enabled?: true, selected_model: 'llama3.1:8b') }
  let(:valid_ai_json) do
    JSON.generate(
      'schema_version' => 1,
      'executive_summary' => 'Trend and structure agree on NIFTY.',
      'indices' => [{ 'index_key' => 'NIFTY', 'bias' => 'BULLISH',
                      'evidence' => [{ 'observation' => 'Trending up', 'source_key' => 'indices.NIFTY.regime.label' }] }],
      'setup_explanation' => nil,
      'no_trade_explanation' => 'Nothing passed the entry guards.',
      'key_risks' => [], 'limitations' => []
    )
  end

  before do
    travel_to(brief_market_open_time)
    stub_market_brief_sources
    allow(Services::Ai::OllamaClient).to receive(:instance).and_return(client)
    allow(client).to receive(:chat).and_return(valid_ai_json)
    allow(Ai::GenerativeAiMarketGate).to receive(:skip?).and_return(false)
  end

  it 'persists the deterministic snapshot and validated AI analysis' do
    described_class.call(report)
    report.reload

    expect(report).to have_attributes(status: 'ready', ai_status: 'completed', ai_model: 'ollama:llama3.1:8b')
    expect(report.snapshot.dig('setup', 'decision')).to eq('NO_TRADE')
    expect(report.snapshot_digest).to eq(Reports::MarketBrief::SnapshotBuilder.digest(report.snapshot))
    expect(report.ai_analysis['executive_summary']).to eq('Trend and structure agree on NIFTY.')
    expect(client).to have_received(:chat).with(hash_including(temperature: 0.1)).once
  end

  it 'sends only snapshot facts — no position rows or credentials — to the model' do
    create(:position_tracker, paper: true)
    described_class.call(report)
    expect(client).to have_received(:chat) do |messages:, **|
      content = messages.last[:content]
      expect(content).to include('"indices":{"NIFTY"')
      expect(content).not_to include('active_positions"', 'order_no', ENV.fetch('DHAN_ACCESS_TOKEN', 'zzz-no-token'))
    end
  end

  it 'keeps the deterministic report when the model returns nothing' do
    allow(client).to receive(:chat).and_return(nil)
    described_class.call(report)
    expect(report.reload).to have_attributes(status: 'ready', ai_status: 'unavailable', ai_error: 'no_response',
                                             ai_analysis: nil)
  end

  it 'marks malformed output invalid without touching the snapshot decision' do
    allow(client).to receive(:chat).and_return('BUY NIFTY 24600 CE NOW')
    described_class.call(report)
    expect(report.reload).to have_attributes(status: 'ready', ai_status: 'invalid', ai_error: 'unparseable_json')
    expect(report.snapshot.dig('setup', 'decision')).to eq('NO_TRADE')
  end

  it 'times out a hanging model and backs off further calls' do
    cache = ActiveSupport::Cache::MemoryStore.new
    allow(Rails).to receive(:cache).and_return(cache)
    allow(client).to receive(:chat).and_raise(Timeout::Error)

    described_class.call(report)
    expect(report.reload).to have_attributes(status: 'ready', ai_status: 'unavailable')
    expect(report.ai_error).to start_with('timeout_after_')

    second, = MarketBriefReport.request!(mode: :paper, now: 10.minutes.from_now)
    described_class.call(second)
    expect(second.reload.ai_error).to eq('provider_backoff_active')
    expect(client).to have_received(:chat).once
  end

  it 'labels a timeout correctly even though OllamaClient swallows the Timeout::Error' do
    stub_const('Reports::MarketBrief::Generator::AI_TIMEOUT', 0.2.seconds)
    allow(client).to receive(:chat) do
      sleep 1
    rescue Timeout::Error
      nil # mirrors OllamaClient#chat's blanket rescue
    end

    described_class.call(report)
    expect(report.reload).to have_attributes(ai_status: 'unavailable', ai_error: 'timeout_after_0s')
  end

  it 'skips AI while the market-closed gate is active' do
    allow(Ai::GenerativeAiMarketGate).to receive(:skip?).with(force: false).and_return(true)
    described_class.call(report)
    expect(report.reload.ai_status).to eq('skipped_market_closed')
    expect(client).not_to have_received(:chat)
  end

  it 'honours force_ai for the market-closed gate' do
    allow(Ai::GenerativeAiMarketGate).to receive(:skip?).with(force: true).and_return(false)
    described_class.call(report, force_ai: true)
    expect(report.reload.ai_status).to eq('completed')
  end

  it 'reports AI as disabled when Ollama is not configured' do
    allow(client).to receive(:enabled?).and_return(false)
    described_class.call(report)
    expect(report.reload).to have_attributes(ai_status: 'disabled', ai_error: 'ollama_not_configured')
  end

  it 'reuses an existing analysis for identical facts instead of calling the model again' do
    described_class.call(report)
    second, = MarketBriefReport.request!(mode: :paper, now: 10.minutes.from_now)
    described_class.call(second)

    expect(second.reload).to have_attributes(ai_status: 'completed', ai_analysis: report.reload.ai_analysis)
    expect(client).to have_received(:chat).once
  end

  it 'builds a report only once even if invoked twice (idempotent job replay)' do
    described_class.call(report)
    described_class.call(MarketBriefReport.find(report.id))
    expect(client).to have_received(:chat).once
  end

  it 'marks the report failed when the snapshot itself cannot be built' do
    allow(Reports::MarketBrief::SnapshotBuilder).to receive(:call).and_raise(ActiveRecord::ConnectionNotEstablished)
    described_class.call(report)
    expect(report.reload).to have_attributes(status: 'failed', error: 'ActiveRecord::ConnectionNotEstablished')
  end

  it 'never places orders or creates positions' do
    expect { described_class.call(report) }.not_to change(PositionTracker, :count)
  end

  describe 'event-driven runs' do
    let(:event_report) do
      MarketBriefReport.request!(mode: :paper, trigger: 'event', reasons: ['NIFTY crossed LTF swing high 24,520.00 upward'],
                                 now: Time.current).first
    end

    it 'sends the trigger reasons to the model so the commentary can explain what changed' do
      described_class.call(event_report)

      expect(client).to have_received(:chat) do |messages:, **|
        expect(messages.last[:content]).to include('"trigger":{"reasons":["NIFTY crossed LTF swing high 24,520.00 upward"]}')
      end
    end

    it 'lets the commentary quote a number that appears in the trigger reasons' do
      json = JSON.parse(valid_ai_json).merge('executive_summary' => 'Price crossed 24,520.00 upward, a level in the facts.')
      allow(client).to receive(:chat).and_return(JSON.generate(json))

      described_class.call(event_report)
      expect(event_report.reload.ai_status).to eq('completed')
    end

    it 'pushes the finished report to open pages' do
      expect(Reports::MarketBrief::Broadcaster).to receive(:report).with(event_report)

      described_class.call(event_report)
    end

    it 'still completes the build when the push fails' do
      allow(ActionCable.server).to receive(:broadcast).and_raise(StandardError, 'cable down')

      described_class.call(event_report)
      expect(event_report.reload).to have_attributes(status: 'ready', ai_status: 'completed')
    end

    it 'does not reuse commentary written for different trigger reasons' do
      described_class.call(report)

      described_class.call(event_report)

      expect(client).to have_received(:chat).twice
    end

    it 'reuses commentary for identical facts and identical reasons' do
      described_class.call(event_report)
      twin = MarketBriefReport.request!(mode: :paper, trigger: 'event', now: 1.second.from_now,
                                        reasons: event_report.trigger_reasons).first
      described_class.call(twin)

      expect(client).to have_received(:chat).once
      expect(twin.reload.ai_status).to eq('completed')
    end
  end
end
