# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Reports::MarketBrief::EventDetector do
  subject(:detector) { described_class.new }

  def frame(swing_high: nil, swing_low: nil, bos: nil)
    { 'swing_high' => swing_high, 'swing_low' => swing_low, 'last_bos' => bos && { 'price' => bos } }
  end

  def index(key, ltp: 24_500.0, regime: 'TRENDING_UP', decision: 'CALL', agreement: 'AGREE', quote: 'live', ltf: frame)
    {
      'index_key' => key,
      'quote' => { 'status' => quote, 'ltp' => ltp },
      'regime' => { 'label' => regime },
      'smc' => { 'decision' => decision, 'timeframes' => { 'htf' => frame, 'mtf' => frame, 'ltf' => ltf } },
      'bias' => { 'agreement' => agreement }
    }
  end

  def snapshot(status: 'open', indices: [index('NIFTY')], entry_allowed: true, breaker: false, feed: 'ok',
               decision: 'NO_TRADE', candidate: nil, positions: 0, utilization: 0.0)
    {
      'generated_at' => '2026-10-27T10:30:00+05:30',
      'session' => { 'status' => status },
      'indices' => indices,
      'market_context' => { 'vix' => { 'entry_allowed' => entry_allowed, 'force_exit_active' => false } },
      'setup' => { 'decision' => decision, 'candidate' => candidate },
      'risk' => { 'active_positions_count' => positions, 'circuit_breaker' => { 'tripped' => breaker },
                  'daily_loss' => { 'utilization_pct' => utilization } },
      'health' => { 'components' => { 'market_feed' => { 'status' => feed } } }
    }
  end

  def kinds(events)
    events.pluck('kind')
  end

  describe 'session and baseline' do
    it 'announces the open on the first observed open snapshot and emits nothing else' do
      events = detector.detect(snapshot(indices: [index('NIFTY', ltp: 24_600.0, ltf: frame(swing_high: 24_480.0))]))

      expect(kinds(events)).to eq(['session_opened'])
      expect(events.first).to include('ai_trigger' => true)
    end

    it 'does not treat a price already beyond a level as a cross at bootstrap' do
      detector.detect(snapshot(indices: [index('NIFTY', ltp: 24_500.0, ltf: frame(swing_high: 24_480.0))]))
      events = detector.detect(snapshot(indices: [index('NIFTY', ltp: 24_505.0, ltf: frame(swing_high: 24_480.0))]))

      expect(kinds(events)).to be_empty
    end

    it 'emits session_closed on the transition out of the session, then re-announces the next open' do
      detector.detect(snapshot)
      closed = detector.detect(snapshot(status: 'post_close'))
      expect(kinds(closed)).to eq(['session_closed'])
      expect(detector.previous).to be_nil

      reopened = detector.detect(snapshot)
      expect(kinds(reopened)).to eq(['session_opened'])
    end

    it 'stays silent while the session is closed' do
      expect(detector.detect(snapshot(status: 'pre_market'))).to eq([])
      expect(detector.previous).to be_nil
    end
  end

  describe 'market state changes' do
    before { detector.detect(snapshot) }

    it 'reports a regime change with both labels and triggers AI' do
      events = detector.detect(snapshot(indices: [index('NIFTY', regime: 'RANGING')]))

      expect(events).to contain_exactly(include('kind' => 'regime_changed', 'index_key' => 'NIFTY',
                                                'from' => 'TRENDING_UP', 'to' => 'RANGING', 'ai_trigger' => true,
                                                'message' => 'NIFTY regime TRENDING_UP → RANGING'))
    end

    it 'reports SMC decision and technical-vs-SMC agreement changes' do
      events = detector.detect(snapshot(indices: [index('NIFTY', decision: 'PUT', agreement: 'CONFLICT')]))

      expect(kinds(events)).to contain_exactly('smc_decision_changed', 'bias_agreement_changed')
    end

    it 'reports a quote going stale as a data-state event that does not trigger AI' do
      events = detector.detect(snapshot(indices: [index('NIFTY', quote: 'stale')]))

      expect(events).to contain_exactly(include('kind' => 'quote_state_changed', 'from' => 'live', 'to' => 'stale',
                                                'ai_trigger' => false))
    end

    it 'ignores transitions from or to unknown values' do
      detector.detect(snapshot(indices: [index('NIFTY', regime: 'UNAVAILABLE')]))
      events = detector.detect(snapshot(indices: [index('NIFTY', regime: 'TRENDING_DOWN')]))

      expect(kinds(events)).to be_empty
    end

    it 'reports VIX gate, circuit breaker, feed, setup decision and position changes' do
      events = detector.detect(snapshot(indices: [index('NIFTY')], entry_allowed: false, breaker: true,
                                        feed: 'down', decision: 'BLOCKED', positions: 2))

      expect(kinds(events)).to contain_exactly('vix_gate_changed', 'circuit_breaker_changed', 'feed_state_changed',
                                               'setup_decision_changed', 'positions_changed')
      expect(events.find { |e| e['kind'] == 'circuit_breaker_changed' }['message']).to eq('Circuit breaker armed → TRIPPED')
      expect(events.find { |e| e['kind'] == 'feed_state_changed' }['ai_trigger']).to be(false)
    end

    it 'reports an approved candidate appearing, with its contract' do
      candidate = { 'signal_id' => 77, 'index_key' => 'NIFTY', 'option_type' => 'CE' }
      events = detector.detect(snapshot(candidate: candidate, decision: 'QUALIFIED'))

      expect(events).to include(include('kind' => 'candidate_appeared', 'signal_id' => 77,
                                        'message' => 'Approved candidate: NIFTY CE (signal #77)'))
    end
  end

  describe 'daily loss bands' do
    before { detector.detect(snapshot(utilization: 45.0)) }

    it 'reports each threshold crossed, once' do
      events = detector.detect(snapshot(utilization: 85.0))
      expect(events.pluck('threshold')).to eq([50, 80])

      expect(detector.detect(snapshot(utilization: 88.0))).to eq([])
    end

    it 'does not report a threshold that is only reached by a decrease' do
      detector.detect(snapshot(utilization: 85.0))
      expect(detector.detect(snapshot(utilization: 40.0))).to eq([])
    end
  end

  # Level 24,480 with a 0.05% band: decided-below is under 24,467.76, decided-above is over 24,492.24.
  # Prices between those edges decide nothing; a cross needs a decided side on each end.
  describe 'level crosses' do
    let(:level) { 24_480.0 }

    def at(ltp, swing_high: level)
      snapshot(indices: [index('NIFTY', ltp: ltp, ltf: frame(swing_high: swing_high))])
    end

    it 'reports an upward cross between two decided sides' do
      detector.detect(at(24_460.0))
      events = detector.detect(at(24_500.0))

      expect(events).to contain_exactly(include('kind' => 'level_crossed', 'index_key' => 'NIFTY',
                                                'label' => 'LTF swing high', 'price' => level, 'direction' => 'upward',
                                                'ltp' => 24_500.0, 'ai_trigger' => true))
    end

    it 'reports a downward cross' do
      detector.detect(at(24_500.0))
      events = detector.detect(at(24_460.0))

      expect(events.first).to include('direction' => 'downward', 'label' => 'LTF swing high')
    end

    it 'does not fire on chop inside the band around the level' do
      detector.detect(at(24_460.0))
      [24_485.0, 24_482.0, 24_486.0, 24_478.0].each do |ltp|
        expect(detector.detect(at(ltp))).to eq([]), "unexpected event at #{ltp}"
      end
    end

    it 'fires once per genuine cross, not on every tick beyond the level' do
      detector.detect(at(24_460.0))
      expect(detector.detect(at(24_500.0)).size).to eq(1)
      expect(detector.detect(at(24_510.0))).to eq([])
      expect(detector.detect(at(24_520.0))).to eq([])
    end

    it 'does not report a level first seen inside the band, nor a refreshed level' do
      detector.detect(at(24_460.0))
      expect(detector.detect(at(24_490.0, swing_high: 24_520.0))).to eq([])
    end

    it 'checks BOS prices as well as swing levels, across timeframes' do
      detector.detect(snapshot(indices: [index('NIFTY', ltp: 24_400.0, ltf: frame(swing_low: 24_290.0, bos: 24_420.0))]))
      events = detector.detect(snapshot(indices: [index('NIFTY', ltp: 24_440.0,
                                                                 ltf: frame(swing_low: 24_290.0, bos: 24_420.0))]))

      expect(events.pluck('label')).to eq(['LTF BOS'])
    end
  end

  describe '.ai_trigger?' do
    it 'is true for kinds that change the commentary and false for data-state kinds' do
      expect(described_class.ai_trigger?('kind' => 'level_crossed')).to be(true)
      expect(described_class.ai_trigger?('kind' => 'quote_state_changed')).to be(false)
      expect(described_class.ai_trigger?('kind' => 'feed_state_changed')).to be(false)
    end
  end
end
