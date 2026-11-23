# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Services::Ai::OllamaClient do
  # Ollama Cloud request policy specs (added alongside the original local-GPU
  # throttle):
  #   * cloud skips the serialized request mutex + inter-request delay
  #   * cloud retries transient failures with exponential backoff (not flat 3 s)
  #   * cloud omits keep_alive; local sends it
  #   * non-retryable client errors (401) fail immediately
  #
  # They run against the real class with the gem's Ollama::Client doubled, the
  # same doubling strategy as the existing ollama_client_spec.rb.

  def with_env(overrides)
    keys = overrides.keys
    saved = keys.index_with { |k| ENV.fetch(k, nil) }
    overrides.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
    yield
  ensure
    saved.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
  end

  def stub_config(use_cloud:, enabled: true)
    allow(AlgoConfig).to receive(:fetch).and_return(
      { ai: { enabled: enabled, ollama_use_cloud: use_cloud } }
    )
  end

  def build_fake_ollama
    instance_double(Ollama::Client).tap do |fake|
      allow(Ollama::Client).to receive(:new).and_return(fake)
    end
  end

  def chat_response(content)
    # OllamaClient#extract_content reads .content (no tools) — a Struct with
    # content alone; response.message&.tool_calls safely nil-paths without tools.
    Struct.new(:content).new(content)
  end

  before do
    described_class.reset_instance!
    described_class.instance_variable_set(:@models_cache, {}) if described_class.respond_to?(:models_cache)
  end

  it 'sends keep_alive on local chat and omits it on cloud chat' do
    local_fake = build_fake_ollama
    with_env('OLLAMA_LOCAL_URL' => 'http://127.0.0.1:11434', 'OLLAMA_API_KEY' => nil) do
      stub_config(use_cloud: false)
      allow(local_fake).to receive(:chat).and_return(chat_response('ok'))
      client = described_class.new
      expect(client.enabled?).to be true
      client.chat(messages: [{ role: 'user', content: 'hi' }], model: 'llama3.2:3b')
      expect(local_fake).to have_received(:chat)
        .with(hash_including(keep_alive: '30m', model: 'llama3.2:3b'))
    end

    described_class.reset_instance!
    cloud_fake = build_fake_ollama
    with_env('OLLAMA_CLOUD_URL' => 'https://ollama.com', 'OLLAMA_API_KEY' => 'secret') do
      stub_config(use_cloud: true)
      allow(cloud_fake).to receive(:chat).and_return(chat_response('ok'))
      client = described_class.new
      expect(client.enabled?).to be true
      client.chat(messages: [{ role: 'user', content: 'hi' }], model: 'minimax-m2.5')
      expect(cloud_fake).to have_received(:chat)
        .with(hash_including(keep_alive: nil, model: 'minimax-m2.5'))
    end
  end

  it 'retries a cloud 429 with exponential backoff instead of flat 3 s' do
    cloud_fake = build_fake_ollama
    with_env(
      'OLLAMA_CLOUD_URL' => 'https://ollama.com',
      'OLLAMA_API_KEY' => 'secret'
    ) do
      stub_config(use_cloud: true)
      # CLOUD_RETRY_BASE is read at class load; stub the constant so this spec
      # observes the exponential sequence (0.01, 0.02) rather than the default (1, 2).
      stub_const("#{described_class}::CLOUD_RETRY_BASE", 0.01)
      sleeps = []
      # rspec-mocks yields the receiver as the block's first argument on
      # any_instance stubs: |_receiver, sec|.
      allow_any_instance_of(described_class).to receive(:sleep) { |_receiver, sec| sleeps << sec }
      allow(cloud_fake).to receive(:chat)
        .and_raise(Ollama::RateLimitError.new('HTTP 429: too many requests', 429))

      client = described_class.new
      # chat() rescues the exhausted retry into nil; the sleeps record the policy.
      client.chat(messages: [{ role: 'user', content: 'hi' }], model: 'minimax-m2.5')

      expect(sleeps).to all(be < 1.0) # exponential from 0.01, never the old flat 3 s
      expect(sleeps.length).to eq(2) # wrapper's 3 attempts = 2 sleeps
    end
  end

  it 'raises immediately on a non-retryable cloud error (401) without sleeping' do
    cloud_fake = build_fake_ollama
    with_env('OLLAMA_CLOUD_URL' => 'https://ollama.com', 'OLLAMA_API_KEY' => 'secret') do
      stub_config(use_cloud: true)
      allow_any_instance_of(described_class).to receive(:sleep) { |*| raise 'must not sleep on non-retryable' }
      allow(cloud_fake).to receive(:chat)
        .and_raise(Ollama::UnauthorizedError.new('HTTP 401: bad key', 401))

      client = described_class.new
      expect(client.chat(messages: [{ role: 'user', content: 'hi' }], model: 'minimax-m2.5')).to be_nil
    end
  end
end
