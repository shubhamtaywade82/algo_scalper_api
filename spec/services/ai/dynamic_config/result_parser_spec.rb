# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::DynamicConfig::ResultParser do
  def suggestion(overrides = {})
    {
      'parameter' => 'capital_alloc_pct',
      'index_key' => 'NIFTY',
      'current' => 0.25,
      'suggested' => 0.20,
      'reason' => 'choppy regime',
      'confidence' => 0.85
    }.merge(overrides)
  end

  def response(changes)
    { 'market_assessment' => { 'regime' => 'choppy', 'iv_environment' => 'high' },
      'parameter_changes' => changes }
  end

  def call(changes, index_key: 'NIFTY', current_config: {}, stressed: false)
    described_class.call(response(changes), index_key: index_key, current_config: current_config, stressed: stressed)
  end

  it 'raises SchemaError when required top-level keys are missing' do
    expect { described_class.call({ 'parameter_changes' => [] }, index_key: 'NIFTY') }
      .to raise_error(described_class::SchemaError)
  end

  it 'raises ParseError on invalid JSON' do
    expect { described_class.call('not json', index_key: 'NIFTY') }.to raise_error(described_class::ParseError)
  end

  it 'accepts a valid in-bounds, high-confidence suggestion and builds a per-index patch' do
    result = call([suggestion])

    expect(result[:parameter_changes].size).to eq(1)
    expect(result[:proposed_patch]).to eq('indices' => [{ 'key' => 'NIFTY', 'capital_alloc_pct' => 0.20 }])
  end

  it 'rejects an unknown parameter name' do
    result = call([suggestion('parameter' => 'yolo_leverage')])

    expect(result[:parameter_changes]).to be_empty
    expect(result[:proposed_patch]).to eq({})
  end

  it 'rejects a suggestion below the confidence threshold' do
    result = call([suggestion('confidence' => 0.5)])

    expect(result[:parameter_changes]).to be_empty
  end

  it 'rejects a suggestion outside the known bounds for that parameter' do
    result = call([suggestion('suggested' => 0.90)])

    expect(result[:parameter_changes]).to be_empty
  end

  it 'rejects a per-index parameter with an unrecognized index_key' do
    result = call([suggestion('index_key' => 'GOLD')])

    expect(result[:parameter_changes]).to be_empty
  end

  it 'rejects a per-index suggestion whose index_key does not match the agent run\'s own index' do
    result = call([suggestion('index_key' => 'BANKNIFTY')], index_key: 'NIFTY')

    expect(result[:parameter_changes]).to be_empty
  end

  it 'builds a top-level patch for a global parameter (empty index_key)' do
    global = suggestion('parameter' => 'sl_pct', 'index_key' => '', 'current' => 0.10, 'suggested' => 0.15)
    result = call([global])

    expect(result[:proposed_patch]).to eq('risk' => { 'sl_pct' => 0.15 })
  end

  it 'merges multiple per-index suggestions for the same index into one indices entry' do
    changes = [
      suggestion,
      suggestion('parameter' => 'cooldown_sec', 'current' => 300, 'suggested' => 400)
    ]
    result = call(changes)

    expect(result[:proposed_patch]).to eq(
      'indices' => [{ 'key' => 'NIFTY', 'capital_alloc_pct' => 0.20, 'cooldown_sec' => 400 }]
    )
  end

  describe 'when stressed (circuit breaker tripped or a losing streak)' do
    let(:current_config) { { capital_alloc_pct: 0.25, cooldown_sec: 300, adx_thresholds: { primary_min_strength: 15 } } }

    it 'blocks a risk-increasing move on a risk-lever param (capital_alloc_pct up)' do
      result = call([suggestion('suggested' => 0.30)], current_config: current_config, stressed: true)

      expect(result[:parameter_changes]).to be_empty
    end

    it 'allows a risk-decreasing move on a risk-lever param (capital_alloc_pct down)' do
      result = call([suggestion('suggested' => 0.15)], current_config: current_config, stressed: true)

      expect(result[:parameter_changes].size).to eq(1)
    end

    it 'blocks lowering cooldown_sec (shorter cooldown = more frequent trades = riskier)' do
      s = suggestion('parameter' => 'cooldown_sec', 'current' => 300, 'suggested' => 120)
      result = call([s], current_config: current_config, stressed: true)

      expect(result[:parameter_changes]).to be_empty
    end

    it 'blocks lowering an ADX threshold (looser entry filter = riskier)' do
      s = suggestion('parameter' => 'primary_adx_min', 'current' => 15, 'suggested' => 10)
      result = call([s], current_config: current_config, stressed: true)

      expect(result[:parameter_changes]).to be_empty
    end

    it 'never blocks tp_pct (no safer_direction policy) regardless of direction' do
      s = suggestion('parameter' => 'tp_pct', 'index_key' => '', 'current' => 0.5, 'suggested' => 0.7)
      result = call([s], current_config: { tp_pct: 0.5 }, stressed: true)

      expect(result[:parameter_changes].size).to eq(1)
    end

    it 'fails closed (blocks) when the authoritative current value is unavailable' do
      result = call([suggestion('suggested' => 0.15)], current_config: {}, stressed: true)

      expect(result[:parameter_changes]).to be_empty
    end

    it 'does not apply the direction gate when not stressed' do
      result = call([suggestion('suggested' => 0.30)], current_config: current_config, stressed: false)

      expect(result[:parameter_changes].size).to eq(1)
    end
  end
end
