# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Agents::DynamicConfigAgent do
  subject(:agent) { described_class.new }

  let(:client) { instance_double(Services::Ai::OllamaClient, enabled?: true, preferred_text_model: 'model', generate: raw_response) }
  let(:raw_response) do
    { 'market_assessment' => { 'regime' => 'choppy', 'iv_environment' => 'high' },
      'parameter_changes' => [
        { 'parameter' => 'capital_alloc_pct', 'index_key' => 'NIFTY', 'current' => 0.25,
          'suggested' => 0.20, 'reason' => 'choppy', 'confidence' => 0.85 }
      ] }
  end

  before do
    allow(Ai::DynamicConfig::ContextBuilder).to receive(:call).and_return({ index_key: 'NIFTY' })
    allow(Ai::DynamicConfig::PromptBuilder).to receive(:call).and_return('prompt')
    allow(Services::Ai::OllamaClient).to receive(:instance).and_return(client)
    allow(AlgoConfig::DocumentStore).to receive(:apply_deep_merge_patch!)
  end

  it 'applies the patch to AlgoConfig::DocumentStore when in paper mode' do
    allow(AlgoConfig).to receive(:paper_trading_enabled?).and_return(true)

    result = agent.run(index_key: 'nifty')

    expect(AlgoConfig::DocumentStore).to have_received(:apply_deep_merge_patch!)
      .with({ 'indices' => [{ 'key' => 'NIFTY', 'capital_alloc_pct' => 0.20 }] },
            source: 'dynamic_config_agent', actor: 'dynamic_config_agent', metadata: { index_key: 'NIFTY' })
    expect(result[:output][:applied]).to be true
  end

  it 'does not apply the patch when paper_trading is disabled (live mode)' do
    allow(AlgoConfig).to receive(:paper_trading_enabled?).and_return(false)

    result = agent.run(index_key: 'NIFTY')

    expect(AlgoConfig::DocumentStore).not_to have_received(:apply_deep_merge_patch!)
    expect(result[:output][:applied]).to be false
  end

  it 'does not apply anything when Ollama is disabled' do
    allow(client).to receive(:enabled?).and_return(false)

    result = agent.run(index_key: 'NIFTY')

    expect(AlgoConfig::DocumentStore).not_to have_received(:apply_deep_merge_patch!)
    expect(result[:output][:note]).to eq('ollama unavailable')
  end

  it 'does not apply anything when the response has no accepted parameter changes' do
    allow(client).to receive(:generate).and_return(
      { 'market_assessment' => { 'regime' => 'neutral', 'iv_environment' => 'fair' }, 'parameter_changes' => [] }
    )
    allow(AlgoConfig).to receive(:paper_trading_enabled?).and_return(true)

    result = agent.run(index_key: 'NIFTY')

    expect(AlgoConfig::DocumentStore).not_to have_received(:apply_deep_merge_patch!)
    expect(result[:output][:applied]).to be false
    expect(result[:confidence]).to eq(0.0)
  end

  it 'logs at authority_level level_2, distinct from the advisor-only agents' do
    allow(AlgoConfig).to receive(:paper_trading_enabled?).and_return(true)

    agent.run(index_key: 'NIFTY')

    log = AgentDecisionLog.where(agent_name: 'dynamic_config_agent').order(:created_at).last
    expect(log.authority_level).to eq('level_2')
  end

  it 'never places, cancels, or modifies an order' do
    allow(AlgoConfig).to receive(:paper_trading_enabled?).and_return(true)

    expect { agent.run(index_key: 'NIFTY') }.not_to change(PositionTracker, :count)
  end

  it 'blocks a risk-increasing suggestion in code when the circuit breaker is tripped, ' \
     'even though it is in-bounds and high-confidence' do
    allow(Ai::DynamicConfig::ContextBuilder).to receive(:call).and_return(
      index_key: 'NIFTY',
      current_config: { capital_alloc_pct: 0.25 },
      risk: { circuit_breaker_tripped: true, recent_consecutive_losses: 0 }
    )
    allow(client).to receive(:generate).and_return(
      { 'market_assessment' => { 'regime' => 'volatile', 'iv_environment' => 'high' },
        'parameter_changes' => [
          { 'parameter' => 'capital_alloc_pct', 'index_key' => 'NIFTY', 'current' => 0.25,
            'suggested' => 0.30, 'reason' => 'model ignored the stress instruction', 'confidence' => 0.9 }
        ] }
    )
    allow(AlgoConfig).to receive(:paper_trading_enabled?).and_return(true)

    result = agent.run(index_key: 'NIFTY')

    expect(AlgoConfig::DocumentStore).not_to have_received(:apply_deep_merge_patch!)
    expect(result[:output][:applied]).to be false
  end
end
