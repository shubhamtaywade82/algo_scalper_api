# frozen_string_literal: true

require 'rails_helper'

RSpec.describe LLMSettings do
  around do |example|
    keys = %w[OLLAMA_MODEL OLLAMA_ANALYSIS_MODEL OLLAMA_BASE_URL]
    saved = keys.index_with { |k| ENV.fetch(k, nil) }
    keys.each { |k| ENV.delete(k) }
    example.run
  ensure
    saved.each { |k, v| v ? ENV[k] = v : ENV.delete(k) }
  end

  it 'uses OLLAMA_MODEL for both tiers when no analysis model is set' do
    ENV['OLLAMA_MODEL'] = 'openbmb/minicpm5-2b'
    expect([described_class.default_model, described_class.analysis_model]).to eq(%w[openbmb/minicpm5-2b openbmb/minicpm5-2b])
  end

  it 'lets OLLAMA_ANALYSIS_MODEL override only the analysis tier' do
    ENV['OLLAMA_MODEL'] = 'openbmb/minicpm5-2b'
    ENV['OLLAMA_ANALYSIS_MODEL'] = 'qwen3:4b'
    expect([described_class.default_model, described_class.analysis_model]).to eq(%w[openbmb/minicpm5-2b qwen3:4b])
  end

  it 'falls back to the local default model when nothing is configured' do
    expect(described_class.analysis_model).to eq(described_class::LOCAL_DEFAULT_MODEL)
  end
end
