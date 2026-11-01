# frozen_string_literal: true

require 'rails_helper'

# The watcher compares its clock with report created_at timestamps, so every example
# runs under travel_to: production uses one clock for both, and so must the spec.
RSpec.describe Reports::MarketBrief::Watcher do
  let(:memory_cache) { ActiveSupport::Cache::MemoryStore.new }
  let(:open_at) { Time.find_zone('Asia/Kolkata').local(2026, 10, 27, 10, 30, 0) }
  let(:snapshots) { [] }
  let(:builder) { ->(_t) { snapshots.shift || snapshot } }
  let(:broadcaster) { class_double(Reports::MarketBrief::Broadcaster, events: nil, report: nil) }
  let(:detector) { Reports::MarketBrief::EventDetector.new }
  let(:watcher) { described_class.new(detector: detector, clock: -> { Time.current }, builder: builder, broadcaster: broadcaster) }

  before do
    travel_to(open_at)
    allow(Rails).to receive(:cache).and_return(memory_cache)
    allow(Market::Calendar).to receive(:trading_day?).and_return(true)
    allow(TradingSession::Service).to receive(:market_closed?).and_return(false)
    allow(AlgoConfig).to receive(:mode).and_return(:paper)
    allow(Services::Ai::OllamaClient.instance).to receive(:enabled?).and_return(true)
    allow(Ai::GenerativeAiMarketGate).to receive(:skip?).and_return(false)
  end

  def snapshot(regime: 'TRENDING_UP', decision: 'CALL', quote: 'live')
    {
      'generated_at' => Time.current.iso8601,
      'session' => { 'status' => 'open' },
      'indices' => [{
        'index_key' => 'NIFTY', 'quote' => { 'status' => quote, 'ltp' => 24_500.0 },
        'regime' => { 'label' => regime }, 'smc' => { 'decision' => decision, 'timeframes' => {} },
        'bias' => { 'agreement' => 'AGREE' }
      }],
      'market_context' => { 'vix' => { 'entry_allowed' => true, 'force_exit_active' => false } },
      'setup' => { 'decision' => 'NO_TRADE', 'candidate' => nil },
      'risk' => { 'active_positions_count' => 0, 'circuit_breaker' => { 'tripped' => false },
                  'daily_loss' => { 'utilization_pct' => 0.0 } },
      'health' => { 'components' => { 'market_feed' => { 'status' => 'ok' } } }
    }
  end

  # Baseline cycle: the first open snapshot announces the open, which starts the opening
  # brief. That run is finished and dated two hours back, so later events are neither
  # debounced by it nor counted against the hourly cap.
  def open_session!
    watcher.cycle
    MarketBriefReport.last.update!(status: 'ready', ai_status: 'completed', created_at: open_at - 2.hours)
  end

  # Marks the last event run finished, as the job would once the LLM returns.
  def finish_last_run!
    MarketBriefReport.last.update!(status: 'ready', ai_status: 'completed')
  end

  describe 'session gating' do
    it 'idles without building a snapshot outside the cash session' do
      allow(TradingSession::Service).to receive(:market_closed?).and_return(true)
      never_built = ->(_t) { raise 'must not build a snapshot while idle' }
      idle = described_class.new(detector: detector, clock: -> { Time.current }, builder: never_built, broadcaster: broadcaster)

      expect(idle.cycle).to eq(status: :idle)
    end

    it 'idles on a non-trading day during clock hours' do
      allow(Market::Calendar).to receive(:trading_day?).and_return(false)
      expect(watcher.cycle).to eq(status: :idle)
    end

    it 'forgets its baseline when idle, so the next open does not compare against yesterday' do
      open_session!
      allow(TradingSession::Service).to receive(:market_closed?).and_return(true)
      watcher.cycle

      expect(detector.previous).to be_nil
    end
  end

  describe 'event publication' do
    it 'records each event in today\'s log and pushes an event frame' do
      open_session!
      snapshots << snapshot(decision: 'PUT')
      expect(broadcaster).to receive(:events).with(hash_including(mode: 'paper',
                                                                  events: [hash_including('kind' => 'smc_decision_changed')]))

      expect(watcher.cycle).to include(status: :running, events: 1)
      expect(Reports::MarketBrief::EventLog.recent('paper').pluck('kind')).to eq(%w[session_opened smc_decision_changed])
    end

    it 'does not start an LLM run for a data-state event' do
      open_session!
      snapshots << snapshot(quote: 'stale')

      expect { watcher.cycle }.not_to have_enqueued_job(Reports::MarketBriefJob)
      expect(MarketBriefReport.where(trigger: 'event').count).to eq(1) # the opening brief only
    end
  end

  describe 'starting an event-driven analysis' do
    it 'creates one event report with the change descriptions and enqueues the job' do
      open_session!
      snapshots << snapshot(regime: 'RANGING')

      result = nil
      expect { result = watcher.cycle }.to have_enqueued_job(Reports::MarketBriefJob).with(kind_of(Integer), 'event', false)
      report = MarketBriefReport.last

      expect(result[:report_id]).to eq(report.id)
      expect(report).to have_attributes(trigger: 'event', mode: 'paper')
      expect(report.trigger_reasons).to eq(['NIFTY regime TRENDING_UP → RANGING'])
    end

    it 'batches changes inside the debounce window into the next run, once the window has passed' do
      open_session!
      snapshots << snapshot(regime: 'RANGING')
      watcher.cycle
      finish_last_run!
      first = MarketBriefReport.last
      expect(first.trigger_reasons).to eq(['NIFTY regime TRENDING_UP → RANGING'])

      travel_to(open_at + 20.seconds)
      snapshots << snapshot(regime: 'RANGING', decision: 'PUT')
      expect(watcher.cycle[:report_id]).to be_nil # inside the 60s window: held
      expect(MarketBriefReport.where(trigger: 'event').count).to eq(2) # opening + first only

      travel_to(open_at + 75.seconds)
      snapshots << snapshot(regime: 'RANGING', decision: 'PUT') # no new event; the held reason is still sent
      expect(watcher.cycle[:report_id]).to be_present
      batched = MarketBriefReport.where(trigger: 'event').latest_first.first
      expect(batched.id).not_to eq(first.id)
      expect(batched.trigger_reasons).to eq(['NIFTY SMC decision CALL → PUT'])
    end

    it 'holds reasons while a previous event run is still building' do
      open_session!
      MarketBriefReport.request!(mode: :paper, trigger: 'event', now: open_at - 5.minutes, reasons: ['older'])
                       .first.update!(status: 'building', created_at: open_at - 5.minutes)
      snapshots << snapshot(regime: 'RANGING')

      expect { watcher.cycle }.not_to have_enqueued_job(Reports::MarketBriefJob)
    end

    it 'does not treat a build stuck past the in-flight window as in flight' do
      open_session!
      MarketBriefReport.request!(mode: :paper, trigger: 'event', now: open_at - 1.hour, reasons: ['dead'])
                       .first.update!(status: 'building', created_at: open_at - 1.hour)
      snapshots << snapshot(regime: 'RANGING')

      expect(watcher.cycle[:report_id]).to be_present
    end

    it 'enforces the hourly cap on event runs' do
      open_session!
      described_class::MAX_AI_RUNS_PER_HOUR.times do |i|
        report, = MarketBriefReport.request!(mode: :paper, trigger: 'event', now: open_at - (i + 2).minutes, reasons: ['x'])
        report.update!(status: 'ready', created_at: open_at - (i + 2).minutes)
      end
      snapshots << snapshot(regime: 'RANGING')

      expect { watcher.cycle }.not_to have_enqueued_job(Reports::MarketBriefJob)
      expect(MarketBriefReport.where(trigger: 'event', created_at: (open_at - 1.hour)..).count)
        .to eq(described_class::MAX_AI_RUNS_PER_HOUR)
    end

    it 'keeps the events but starts no run when AI is disabled in configuration' do
      open_session!
      allow(AlgoConfig).to receive(:fetch).and_return(ai: { enabled: false })
      snapshots << snapshot(regime: 'RANGING')

      expect { watcher.cycle }.not_to have_enqueued_job(Reports::MarketBriefJob)
      expect(MarketBriefReport.where(trigger: 'event').count).to eq(1) # the opening brief only
      expect(Reports::MarketBrief::EventLog.recent('paper').pluck('kind')).to include('regime_changed')
    end

    it 'starts no run when the provider is unavailable' do
      open_session!
      allow(Services::Ai::OllamaClient.instance).to receive(:enabled?).and_return(false)
      snapshots << snapshot(regime: 'RANGING')

      expect(watcher.cycle[:report_id]).to be_nil
    end

    it 'starts no run while the provider is in backoff' do
      open_session!
      memory_cache.write(Reports::MarketBrief::Generator::AI_BACKOFF_KEY, 4.minutes.from_now.to_i)
      snapshots << snapshot(regime: 'RANGING')

      expect(watcher.cycle[:report_id]).to be_nil
    end

    it 'starts no run while the market-closed AI gate is active' do
      open_session!
      allow(Ai::GenerativeAiMarketGate).to receive(:skip?).and_return(true)
      snapshots << snapshot(regime: 'RANGING')

      expect(watcher.cycle[:report_id]).to be_nil
    end
  end

  describe 'failure isolation' do
    it 'turns a cycle exception into an error status in the loop wrapper' do
      failing = ->(_t) { raise Redis::CannotConnectError, 'redis down' }
      broken = described_class.new(detector: detector, clock: -> { Time.current }, builder: failing, broadcaster: broadcaster)

      expect(broken.send(:safe_cycle)).to eq(status: :error)
    end
  end

  describe 'loop lifecycle' do
    it 'starts once, and stops by clearing its thread' do
      loop_watcher = described_class.new(detector: detector, clock: -> { Time.current }, builder: builder, broadcaster: broadcaster)

      loop_watcher.start
      loop_watcher.start
      thread = loop_watcher.instance_variable_get(:@thread)
      expect(thread).to be_alive

      loop_watcher.stop
      expect(loop_watcher.instance_variable_get(:@thread)).to be_nil
      expect(thread).not_to be_alive
    end
  end
end
