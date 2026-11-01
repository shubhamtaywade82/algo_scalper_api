# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Reports::MarketBrief::AiResponseValidator do
  subject(:result) { described_class.new(snapshot).call(raw) }

  let(:snapshot) do
    Reports::MarketBrief::SnapshotBuilder.call
  end
  let(:payload) do
    {
      'schema_version' => 1,
      'executive_summary' => 'NIFTY trends higher with ADX at 31.42 and aligned SMC structure.',
      'indices' => [
        {
          'index_key' => 'NIFTY',
          'bias' => 'BULLISH',
          'evidence' => [
            { 'observation' => 'Regime is TRENDING_UP', 'source_key' => 'indices.NIFTY.regime.label' },
            { 'observation' => 'All three timeframes bullish', 'source_key' => 'indices.NIFTY.bias.mtf_alignment' }
          ],
          'conflicts' => [],
          'bullish_scenario' => { 'condition' => 'Structure holds above the last BOS', 'invalidation' => 'LTF CHoCH lower' },
          'bearish_scenario' => nil
        }
      ],
      'setup_explanation' => nil,
      'no_trade_explanation' => 'No signal passed the entry guards today.',
      'key_risks' => ['VIX at 13.25 can expand quickly'],
      'limitations' => ['Supertrend snapshot unavailable']
    }
  end
  let(:raw) { JSON.generate(payload) }

  before do
    travel_to(brief_market_open_time)
    stub_market_brief_sources
  end

  it 'accepts a grounded response and keeps the deterministic decision' do
    expect(result).to be_valid
    analysis = result.analysis
    expect(analysis['indices'].first).to include('index_key' => 'NIFTY', 'bias' => 'BULLISH')
    expect(analysis['indices'].first['evidence'].size).to eq(2)
    expect(analysis['no_trade_explanation']).to be_present
    expect(analysis['validation']['dropped']).to eq([])
  end

  it 'parses JSON wrapped in markdown code fences' do
    raw = "Here you go:\n```json\n#{JSON.generate(payload)}\n```"
    expect(described_class.new(snapshot).call(raw)).to be_valid
  end

  it 'rejects empty, non-JSON and oversized output' do
    validator = described_class.new(snapshot)
    expect(validator.call('').errors).to eq(['unparseable_json'])
    expect(validator.call('The market looks bullish').errors).to eq(['unparseable_json'])
    expect(validator.call("{#{'x' * 70_000}}").status).to eq(:invalid)
  end

  it 'rejects an unknown schema version' do
    payload['schema_version'] = 2
    expect(result.errors).to eq(['schema_version_mismatch'])
  end

  it 'drops evidence citing paths that do not exist in the snapshot' do
    payload['indices'].first['evidence'] << { 'observation' => 'FII bought heavily', 'source_key' => 'flows.fii.net' }
    expect(result).to be_valid
    expect(result.analysis['indices'].first['evidence'].size).to eq(2)
    expect(result.analysis['validation']['dropped'].first['reason']).to start_with('unknown_source_key:flows.fii.net')
  end

  it 'invalidates the response when most references are fabricated' do
    payload['indices'].first['evidence'] = [
      { 'observation' => 'a', 'source_key' => 'news.headline' },
      { 'observation' => 'b', 'source_key' => 'breadth.adv' },
      { 'observation' => 'c', 'source_key' => 'indices.NIFTY.regime.label' }
    ]
    expect(result.status).to eq(:invalid)
    expect(result.errors.first).to start_with('too_many_unsupported_references')
  end

  it 'drops free text that quotes numbers absent from the snapshot (invented levels)' do
    payload['indices'].first['bullish_scenario'] = { 'condition' => 'Buy above 24650', 'invalidation' => 'Below 24380' }
    expect(result).to be_valid
    expect(result.analysis['indices'].first['bullish_scenario']).to be_nil
    expect(result.analysis['validation']['dropped'].pluck('reason')).to include(start_with('unsupported_numbers'))
  end

  it 'invalidates the report when the executive summary invents a number' do
    payload['executive_summary'] = 'NIFTY likely to hit 25000 today.'
    expect(result.errors).to eq(['executive_summary_missing_or_unsupported'])
  end

  it 'refuses a setup explanation when the deterministic decision is not QUALIFIED' do
    payload['setup_explanation'] = 'Take the CE now.'
    expect(result.analysis['setup_explanation']).to be_nil
    expect(result.analysis['validation']['dropped']).to include(
      'field' => 'setup_explanation', 'reason' => 'contradicts_deterministic_decision'
    )
  end

  it 'refuses a no-trade explanation when a candidate is QUALIFIED' do
    approved_signal
    payload['no_trade_explanation'] = 'Stay out.'
    payload['setup_explanation'] = 'Approved by the guard pipeline.'
    expect(result.analysis['no_trade_explanation']).to be_nil
    expect(result.analysis['setup_explanation']).to eq('Approved by the guard pipeline.')
  end

  it 'downgrades an unsupported bias to UNAVAILABLE' do
    payload['indices'].first['evidence'] = []
    payload['indices'] << { 'index_key' => 'SENSEX', 'bias' => 'BEARISH', 'evidence' => [] }
    biases = result.analysis['indices'].to_h { |i| [i['index_key'], i['bias']] }
    expect(biases).to eq('NIFTY' => 'UNAVAILABLE', 'SENSEX' => 'UNAVAILABLE')
  end

  it 'drops unknown and duplicate indices' do
    payload['indices'] << payload['indices'].first.dup << payload['indices'].first.merge('index_key' => 'FINNIFTY')
    expect(result.analysis['indices'].pluck('index_key')).to eq(['NIFTY'])
  end

  it 'surfaces (but does not resolve) a disagreement with the deterministic bias' do
    payload['indices'].first['bias'] = 'BEARISH'
    expect(result.analysis['disagreements']).to eq([
                                                     { 'index_key' => 'NIFTY', 'ai_bias' => 'BEARISH',
                                                       'deterministic_technical' => 'BULLISH', 'deterministic_smc' => 'BULLISH' }
                                                   ])
    expect(snapshot.dig('setup', 'decision')).to eq('NO_TRADE')
  end

  it 'strips markup from model text' do
    payload['executive_summary'] = '<script>alert(1)</script>Trend intact.'
    expect(result.analysis['executive_summary']).to eq('alert(1)Trend intact.')
  end
end
