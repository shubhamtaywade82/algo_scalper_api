# frozen_string_literal: true

require 'rails_helper'

RSpec.describe LLMSettings do
  def with_env(vars)
    stub_const('ENV', ENV.to_h.except('OLLAMA_BASE_URL', 'OLLAMA_MODEL', 'OLLAMA_API_KEY', 'OLLAMA_TIMEOUT').merge(vars))
  end

  it 'defaults to local Ollama with a /v1 base for the Chat Completions client' do
    with_env({})
    expect(described_class.provider).to eq(:ollama)
    expect(described_class.api_base).to eq('http://localhost:11434/v1')
    expect(described_class.default_model).to eq('llama3.2:3b')
    expect(described_class.request_timeout).to eq(60)
  end

  it 'does not double the /v1 suffix' do
    with_env('OLLAMA_BASE_URL' => 'http://gpu-box:11434/v1/')
    expect(described_class.api_base).to eq('http://gpu-box:11434/v1')
  end

  it 'selects the Ollama Cloud provider (separate credentials in RubyLLM 2.x) for ollama.com' do
    with_env('OLLAMA_BASE_URL' => 'https://ollama.com', 'OLLAMA_API_KEY' => 'k')
    expect(described_class.provider).to eq(:ollama_cloud)
    expect(described_class.api_base).to eq('https://ollama.com/v1')
    expect(described_class.default_model).to eq('minimax-m2.5') # local default is not a cloud model
    expect(described_class.api_key).to eq('k')
  end

  it 'honours an explicit model and ignores a malformed timeout' do
    with_env('OLLAMA_MODEL' => 'gpt-oss:20b', 'OLLAMA_TIMEOUT' => 'abc')
    expect(described_class.default_model).to eq('gpt-oss:20b')
    expect(described_class.request_timeout).to eq(60)
  end

  it 'is applied to RubyLLM at boot' do
    expect(RubyLLM.config.ollama_api_base).to eq(described_class.api_base)
    expect(RubyLLM.config.default_model).to eq(described_class.default_model)
  end
end
