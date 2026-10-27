# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Reports::MarketBrief::SetupSelector do
  before do
    travel_to(brief_market_open_time)
    stub_market_brief_sources
  end

  def setup
    Reports::MarketBrief::SnapshotBuilder.call['setup']
  end

  it 'returns NO_TRADE with the standard message when nothing was approved today' do
    expect(setup).to include('decision' => 'NO_TRADE', 'candidate' => nil, 'blockers' => [],
                             'message' => described_class::NO_TRADE_MESSAGE)
  end

  it 'aggregates guard rejection reasons, most frequent first' do
    2.times { blocked_signal(reason: 'spread_too_wide') }
    blocked_signal(reason: 'adx_below_threshold')

    expect(setup['decision']).to eq('NO_TRADE')
    expect(setup['rejection_reasons']).to eq([
                                               { 'reason' => 'spread_too_wide', 'count' => 2 },
                                               { 'reason' => 'adx_below_threshold', 'count' => 1 }
                                             ])
    expect(setup['evaluated_count']).to eq(3)
  end

  it 'picks the most recent guard-approved signal deterministically among several' do
    approved_signal(index_key: 'NIFTY', emitted_at: 40.minutes.ago)
    latest = approved_signal(index_key: 'BANKNIFTY', action: 'buy_put', emitted_at: 5.minutes.ago)
    approved_signal(index_key: 'SENSEX', emitted_at: 1.day.ago) # yesterday — never a candidate

    result = setup
    expect(result['decision']).to eq('QUALIFIED')
    expect(result['approved_count']).to eq(2)
    expect(result['candidate']).to include('signal_id' => latest.id, 'index_key' => 'BANKNIFTY', 'option_type' => 'PE',
                                           'trade_link_status' => 'not_linked', 'trade' => nil)
  end

  it 'takes trade levels only from the linked position tracker' do
    tracker = create(:position_tracker, paper: true, entry_price: 100, quantity: 75, atm_strike: 24_500,
                                        expiry_date: Date.new(2026, 10, 28), premium_stop_price: 88)
    approved_signal(tracker: tracker)

    trade = setup['candidate']['trade']
    expect(trade).to include('position_tracker_id' => tracker.id, 'entry_price' => 100.0, 'quantity' => 75,
                             'capital_required' => 7_500.0, 'strike' => 24_500.0, 'expiry' => '2026-10-28')
    expect(trade['stop_loss']).to be < 100.0
    expect(trade['target']).to be > 100.0
    expected_rr = ((trade['target'] - 100.0) / (100.0 - trade['stop_loss'])).round(2)
    expect(trade['reward_to_risk']).to eq(expected_rr)
  end

  it 'ignores non-directional and shadow signals' do
    create(:strategy_signal, action: 'hold', outcome: 'executed')
    create(:strategy_signal, action: 'buy_call', outcome: 'shadow')
    expect(setup).to include('decision' => 'NO_TRADE', 'evaluated_count' => 1)
  end

  context 'with systemic blockers' do
    before { approved_signal }

    it 'BLOCKS when the circuit breaker is tripped even if a candidate was approved' do
      stub_market_brief_sources(breaker_tripped: true)
      expect(setup['decision']).to eq('BLOCKED')
      expect(setup['blockers']).to include('circuit_breaker_tripped')
      expect(setup['candidate']).to be_present
    end

    it 'BLOCKS on the VIX gate, an exhausted loss limit, a dead feed and stale quotes' do
      stub_market_brief_sources(vix_entry_allowed: false, daily_loss: 4_000.0, feed_alive: false, quote_age: 5.minutes)
      expect(setup['blockers']).to include('vix_gate_blocks_entries', 'daily_loss_limit_reached',
                                           'market_feed_down', 'no_live_index_quotes')
    end
  end
end
