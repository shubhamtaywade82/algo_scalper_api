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

  it 'raises SchemaError when required top-level keys are missing' do
    expect { described_class.call({ 'parameter_changes' => [] }) }
      .to raise_error(described_class::SchemaError)
  end

  it 'raises ParseError on invalid JSON' do
    expect { described_class.call('not json') }.to raise_error(described_class::ParseError)
  end

  it 'accepts a valid in-bounds, high-confidence suggestion and builds a per-index patch' do
    result = described_class.call(response([suggestion]))

    expect(result[:parameter_changes].size).to eq(1)
    expect(result[:proposed_patch]).to eq('indices' => [{ 'key' => 'NIFTY', 'capital_alloc_pct' => 0.20 }])
  end

  it 'rejects an unknown parameter name' do
    result = described_class.call(response([suggestion('parameter' => 'yolo_leverage')]))

    expect(result[:parameter_changes]).to be_empty
    expect(result[:proposed_patch]).to eq({})
  end

  it 'rejects a suggestion below the confidence threshold' do
    result = described_class.call(response([suggestion('confidence' => 0.5)]))

    expect(result[:parameter_changes]).to be_empty
  end

  it 'rejects a suggestion outside the known bounds for that parameter' do
    result = described_class.call(response([suggestion('suggested' => 0.90)]))

    expect(result[:parameter_changes]).to be_empty
  end

  it 'rejects a per-index parameter with an unrecognized index_key' do
    result = described_class.call(response([suggestion('index_key' => 'GOLD')]))

    expect(result[:parameter_changes]).to be_empty
  end

  it 'builds a top-level patch for a global parameter (empty index_key)' do
    global = suggestion('parameter' => 'sl_pct', 'index_key' => '', 'current' => 0.10, 'suggested' => 0.15)
    result = described_class.call(response([global]))

    expect(result[:proposed_patch]).to eq('risk' => { 'sl_pct' => 0.15 })
  end

  it 'merges multiple per-index suggestions for the same index into one indices entry' do
    changes = [
      suggestion,
      suggestion('parameter' => 'cooldown_sec', 'current' => 300, 'suggested' => 400)
    ]
    result = described_class.call(response(changes))

    expect(result[:proposed_patch]).to eq(
      'indices' => [{ 'key' => 'NIFTY', 'capital_alloc_pct' => 0.20, 'cooldown_sec' => 400 }]
    )
  end
end
