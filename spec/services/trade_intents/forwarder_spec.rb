# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TradeIntents::Forwarder do
  let(:index_cfg) { { key: 'NIFTY', segment: 'IDX_I', sid: '13' } }
  let(:signal) { { strategy: 'supertrend-adx', strategy_version: 3, signal_id: nil, confidence: 0.72, reasons: ['adx_confirmed'] } }
  let(:config) { { execution: { engine: 'agent', intent_ttl_seconds: 20 }, paper_trading: { enabled: true } } }
  let(:pass) { Entries::EntryGuardPipeline::PASS }

  before do
    allow(AlgoConfig).to receive(:fetch).and_return(config)
    allow(TradingSession::Service).to receive(:market_closed?).and_return(false)
    described_class::PRE_CHECKS.each { |guard| allow(guard).to receive(:call).and_return(pass) }
    allow(Live::TickQuery).to receive(:for_security).and_return(nil)
  end

  def forward(direction: :bullish)
    described_class.forward(index_cfg: index_cfg, direction: direction, signal: signal)
  end

  it 'stores a trade-intent/1 payload that validates against the shared contract' do
    result = forward

    expect(result).to be_forwarded
    intent = result.intent
    expect(intent).to have_attributes(underlying: 'NIFTY', direction: 'BULLISH', mode: 'paper', source_strategy: 'supertrend-adx')
    expect(Contracts::Schema.errors('trade-intent-1', intent.payload)).to be_empty
    expect(intent.expires_at).to be_within(1.second).of(20.seconds.from_now)
  end

  it 'maps a bearish signal to a BEARISH intent' do
    expect(forward(direction: :bearish).intent.direction).to eq('BEARISH')
  end

  it 'forwards at most one pending intent per underlying and direction' do
    forward

    second = forward
    expect(second).not_to be_forwarded
    expect(second.blocked_reason).to eq('intent_already_pending')
    expect(forward(direction: :bearish)).to be_forwarded
  end

  it 'refuses outside paper mode for now' do
    config[:paper_trading][:enabled] = false

    expect(forward.blocked_reason).to eq('agent_intake_paper_only')
    expect(TradeIntent.count).to eq(0)
  end

  it 'refuses while the market is closed' do
    allow(TradingSession::Service).to receive(:market_closed?).and_return(true)

    expect(forward.blocked_reason).to eq('market_closed')
  end

  it 'returns the first failing pre-check and stores nothing' do
    allow(Entries::Guards::CircuitBreakerGuard).to receive(:call).and_return({ blocked: 'circuit breaker tripped' })

    expect(forward.blocked_reason).to eq('circuit breaker tripped')
    expect(TradeIntent.count).to eq(0)
  end

  it 'marks a signal without a score as unscored' do
    signal[:confidence] = nil

    expect(forward.intent.confidence).to eq(described_class::UNSCORED_CONFIDENCE)
  end

  describe '.agent_engine?' do
    it 'is true only when execution.engine is agent' do
      expect(described_class.agent_engine?).to be(true)

      config[:execution][:engine] = 'rails'
      expect(described_class.agent_engine?).to be(false)
    end
  end
end
