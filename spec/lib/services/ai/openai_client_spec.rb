# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Services::Ai::OpenaiClient do
  let(:klass) { described_class }

  def reset_client_state!
    klass.instance_variable_set(:@instance, nil)
    klass.models_cache = {}
  end

  def stub_env(hash)
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:fetch).and_call_original
    hash.each do |key, value|
      allow(ENV).to receive(:[]).with(key).and_return(value)
      # Cover both ENV.fetch(key) and ENV.fetch(key, default) call styles
      allow(ENV).to receive(:fetch).with(key).and_return(value)
      allow(ENV).to receive(:fetch).with(key, anything).and_return(value)
    end
  end

  before do
    reset_client_state!
    allow(AlgoConfig).to receive(:fetch).and_return({})
    allow(Rails.logger).to receive(:info)
    allow(Rails.logger).to receive(:warn)
    allow(Rails.logger).to receive(:error)
    allow(Rails.logger).to receive(:debug)
    # Default env: no ollama, no provider, no API keys
    stub_env(
      'OLLAMA_HOST_URL' => nil, 'OLLAMA_BASE_URL' => nil, 'OPENAI_PROVIDER' => nil,
      'OPENAI_API_KEY' => nil, 'OPENAI_ACCESS_TOKEN' => nil, 'OLLAMA_MODEL' => nil
    )
  end

  after { reset_client_state! }

  describe '.instance' do
    it 'memoizes the instance' do
      expect(klass.instance).to equal(klass.instance)
    end
  end

  describe '#initialize / provider determination' do
    it 'detects ollama when OLLAMA_HOST_URL is set' do
      stub_env('OLLAMA_HOST_URL' => 'http://localhost:11434')
      client = klass.new
      expect(client.provider).to eq(:ollama)
    end

    it 'detects ollama when OLLAMA_BASE_URL is set' do
      stub_env('OLLAMA_BASE_URL' => 'http://ollama.internal:11434')
      client = klass.new
      expect(client.provider).to eq(:ollama)
    end

    it 'uses OPENAI_PROVIDER when set to a known value' do
      stub_env('OPENAI_PROVIDER' => 'ruby_openai')
      expect(klass.new.provider).to eq(:ruby_openai)
    end

    it 'falls back to ruby_openai in a local env' do
      allow(Rails.env).to receive(:local?).and_return(true)
      expect(klass.new.provider).to eq(:ruby_openai)
    end

    it 'falls back to openai_ruby in a non-local env' do
      allow(Rails.env).to receive(:local?).and_return(false)
      expect(klass.new.provider).to eq(:openai_ruby)
    end
  end

  describe '#enabled? / check_enabled' do
    it 'is disabled when config explicitly disables AI' do
      allow(AlgoConfig).to receive(:fetch).and_return(ai: { enabled: false })
      expect(klass.new).not_to be_enabled
    end

    it 'is disabled for ollama without a base URL (unreachable: provider requires URL)' do
      # provider is :ollama only when a URL is present, so this state is
      # constructed directly; check_enabled must fail closed without a URL.
      client = klass.allocate
      client.instance_variable_set(:@provider, :ollama)
      expect(client.send(:check_enabled)).to be false
    end

    it 'is enabled for ollama with a base URL (client init may still fail on missing gem)' do
      stub_env('OLLAMA_HOST_URL' => 'http://localhost:11434')
      client = klass.new
      expect(client.provider).to eq(:ollama)
      # The gem ruby-openai is not bundled, so initialize_client fails and
      # disables the client — check_enabled itself returns true:
      client2 = klass.allocate
      client2.instance_variable_set(:@provider, :ollama)
      stub_env('OLLAMA_BASE_URL' => 'http://localhost:11434')
      expect(client2.send(:check_enabled)).to be true
    end

    it 'is disabled for openai providers without an API key' do
      client = klass.allocate
      client.instance_variable_set(:@provider, :openai_ruby)
      expect(client.send(:check_enabled)).to be false
    end

    it 'check_enabled accepts OPENAI_ACCESS_TOKEN as the key' do
      client = klass.allocate
      client.instance_variable_set(:@provider, :openai_ruby)
      stub_env('OPENAI_ACCESS_TOKEN' => 'tok')
      expect(client.send(:check_enabled)).to be true
    end
  end

  describe '#ollama_base_url' do
    it 'prefers OLLAMA_HOST_URL' do
      stub_env('OLLAMA_HOST_URL' => 'http://host-url', 'OLLAMA_BASE_URL' => 'http://base-url')
      expect(klass.new.ollama_base_url).to eq('http://host-url')
    end

    it 'falls back to OLLAMA_BASE_URL' do
      stub_env('OLLAMA_BASE_URL' => 'http://base-url')
      expect(klass.new.ollama_base_url).to eq('http://base-url')
    end

    it 'defaults to localhost:11434' do
      expect(klass.new.ollama_base_url).to eq('http://localhost:11434')
    end
  end

  describe '#with_request_serialization' do
    it 'passes through without a mutex for non-ollama providers' do
      client = klass.allocate
      client.instance_variable_set(:@provider, :ruby_openai)
      expect(described_class::REQUEST_MUTEX).not_to receive(:synchronize)
      expect(client.with_request_serialization { :result }).to eq(:result)
    end

    it 'serializes and sets last_request_time for ollama' do
      client = klass.allocate
      client.instance_variable_set(:@provider, :ollama)
      client.instance_variable_set(:@last_request_time, nil)
      result = nil
      expect(described_class::REQUEST_MUTEX).to receive(:synchronize).and_wrap_original do |m, &block|
        result = block.call
      end
      client.with_request_serialization { :serialized }
      expect(result).to eq(:serialized)
      expect(client.instance_variable_get(:@last_request_time)).to be_present
    end

    it 'sleeps to honor the inter-request delay when the last request was recent' do
      client = klass.allocate
      client.instance_variable_set(:@provider, :ollama)
      client.instance_variable_set(:@last_request_time, Time.current)
      expect(client).to receive(:sleep).with(a_value >= 0.0)
      client.with_request_serialization { :ok }
    end

    it 'does not sleep when the last request is older than the delay' do
      client = klass.allocate
      client.instance_variable_set(:@provider, :ollama)
      client.instance_variable_set(:@last_request_time, 10.seconds.ago)
      expect(client).not_to receive(:sleep)
      client.with_request_serialization { :ok }
    end
  end

  describe 'class-level models cache' do
    it 'stores and returns models per base URL' do
      klass.set_cached_models('http://a', ['llama3.1:8b'])
      expect(klass.get_cached_models('http://a')).to eq(['llama3.1:8b'])
      expect(klass.get_cached_models('http://b')).to be_nil
    end

    it 'expires entries older than MODELS_CACHE_TTL' do
      klass.models_cache['http://a'] = { models: ['x'], fetched_at: (described_class::MODELS_CACHE_TTL + 10).seconds.ago }
      expect(klass.get_cached_models('http://a')).to be_nil
      expect(klass.models_cache).not_to have_key('http://a')
    end

    it 'returns cached models while fresh' do
      klass.models_cache['http://a'] = { models: ['x'], fetched_at: Time.current }
      expect(klass.get_cached_models('http://a')).to eq(['x'])
    end
  end

  describe '#text_capable_ollama_model?' do
    it 'rejects vision-first models' do
      client = klass.allocate
      %w[llava llava:13b minicpm-v qwen-vl some-vl-model VisionModel].each do |name|
        expect(client.send(:text_capable_ollama_model?, name)).to be false
      end
    end

    it 'accepts text models' do
      client = klass.allocate
      %w[llama3.1:8b mistral:7b phi3:mini].each do |name|
        expect(client.send(:text_capable_ollama_model?, name)).to be true
      end
    end

    it 'rejects blank names' do
      expect(klass.allocate.send(:text_capable_ollama_model?, nil)).to be false
      expect(klass.allocate.send(:text_capable_ollama_model?, '')).to be false
    end
  end

  describe '#select_best_model' do
    def client_with(models:, provider: :ollama)
      client = klass.allocate
      client.instance_variable_set(:@provider, provider)
      client.instance_variable_set(:@available_models, models)
      client.instance_variable_set(:@selected_model, nil)
      client
    end

    it 'returns nil for non-ollama providers' do
      expect(client_with(models: ['llama3.1:8b'], provider: :ruby_openai).select_best_model).to be_nil
    end

    it 'uses the explicit OLLAMA_MODEL when it is available and text-capable' do
      stub_env('OLLAMA_MODEL' => 'mistral:7b')
      client = client_with(models: %w[mistral:7b llama3.1:8b])
      expect(client.select_best_model).to eq('mistral:7b')
      expect(client.selected_model).to eq('mistral:7b')
    end

    it 'ignores an explicit model that is not in the available list' do
      stub_env('OLLAMA_MODEL' => 'not-there')
      client = client_with(models: ['llama3.1:8b'])
      expect(client.select_best_model).to eq('llama3.1:8b')
    end

    it 'ignores an explicit model that is vision-first' do
      stub_env('OLLAMA_MODEL' => 'llava:13b')
      client = client_with(models: %w[llava:13b llama3.1:8b])
      expect(client.select_best_model).to eq('llama3.1:8b')
    end

    it 'selects by priority order when no explicit model is set' do
      client = client_with(models: %w[phi3:mini llama3.1:8b gemma:2b])
      expect(client.select_best_model).to eq('llama3.1:8b')
    end

    it 'falls back to the first text-capable model when no priority model matches' do
      client = client_with(models: %w[custom-model other-model])
      expect(client.select_best_model).to eq('custom-model')
    end

    it 'falls back to the first available model when all are vision-first' do
      client = client_with(models: %w[llava:13b qwen-vl])
      expect(client.select_best_model).to eq('llava:13b')
    end

    it 'returns nil when no models are available' do
      expect(client_with(models: []).select_best_model).to be_nil
      expect(client_with(models: nil).select_best_model).to be_nil
    end
  end

  describe '#preferred_text_model' do
    def client_with(models: nil, selected: nil, provider: :ollama)
      client = klass.allocate
      client.instance_variable_set(:@provider, provider)
      client.instance_variable_set(:@available_models, models)
      client.instance_variable_set(:@selected_model, selected)
      client
    end

    it 'returns the default for non-ollama providers' do
      expect(client_with(provider: :ruby_openai).preferred_text_model(default: 'd')).to eq('d')
    end

    it 'fetches and selects a model when none is known yet' do
      client = client_with(models: nil, selected: nil)
      expect(client).to receive(:fetch_and_select_model)
      allow(client).to receive(:text_capable_ollama_model?).and_return(true)
      stub_env('OLLAMA_MODEL' => 'mistral:7b')
      expect(client.preferred_text_model(default: 'd')).to eq('mistral:7b')
    end

    it 'returns an explicit text-capable OLLAMA_MODEL directly' do
      stub_env('OLLAMA_MODEL' => 'mistral:7b')
      client = client_with(models: %w[mistral:7b], selected: nil)
      expect(client.preferred_text_model(default: 'd')).to eq('mistral:7b')
    end

    it 'ignores a vision-first explicit OLLAMA_MODEL' do
      stub_env('OLLAMA_MODEL' => 'llava')
      client = client_with(models: %w[mistral:7b llava], selected: 'mistral:7b')
      expect(client.preferred_text_model(default: 'd')).to eq('mistral:7b')
    end

    it 'uses the selected model when text-capable' do
      client = client_with(models: %w[mistral:7b], selected: 'mistral:7b')
      expect(client.preferred_text_model(default: 'd')).to eq('mistral:7b')
    end

    it 'falls back to the default when nothing text-capable exists' do
      client = client_with(models: %w[llava], selected: nil)
      stub_env('OLLAMA_MODEL' => nil)
      expect(client.preferred_text_model(default: 'fallback-model')).to eq('fallback-model')
    end
  end

  describe '#generate' do
    it 'returns nil when disabled' do
      client = klass.allocate
      client.instance_variable_set(:@enabled, false)
      client.instance_variable_set(:@provider, :ollama)
      expect(client.generate(prompt: 'hi')).to be_nil
    end

    context 'with an enabled ollama client' do
      let(:client) do
        c = klass.allocate
        c.instance_variable_set(:@enabled, true)
        c.instance_variable_set(:@provider, :ollama)
        c.instance_variable_set(:@selected_model, 'llama3.1:8b')
        c.instance_variable_set(:@last_request_time, 10.seconds.ago)
        c
      end

      it 'POSTs to the ollama generate endpoint and returns the response text' do
        stub_request(:post, 'http://localhost:11434/api/generate')
          .to_return(status: 200, body: { response: 'the answer' }.to_json)

        expect(client.generate(prompt: 'say hi')).to eq('the answer')
      end

      it 'parses structured JSON when a schema is provided' do
        stub_request(:post, 'http://localhost:11434/api/generate')
          .to_return(status: 200, body: { response: '{"sentiment":"bullish"}' }.to_json)

        expect(client.generate(prompt: 'analyze', schema: { type: 'object' }))
          .to eq({ 'sentiment' => 'bullish' })
      end

      it 'returns nil on a non-200 response' do
        stub_request(:post, 'http://localhost:11434/api/generate')
          .to_return(status: 500, body: 'boom')

        expect(client.generate(prompt: 'hi')).to be_nil
      end

      it 'returns nil when the connection fails' do
        stub_request(:post, 'http://localhost:11434/api/generate')
          .to_raise(Errno::ECONNREFUSED.new('refused'))

        expect(client.generate(prompt: 'hi')).to be_nil
      end

      it 'falls back to OLLAMA_MODEL when no model was selected' do
        stub_env('OLLAMA_MODEL' => 'mistral:7b')
        client.instance_variable_set(:@selected_model, nil)
        stub_request(:post, 'http://localhost:11434/api/generate')
          .to_return(status: 200, body: { response: 'ok' }.to_json)

        expect(client.generate(prompt: 'hi')).to eq('ok')
      end
    end
  end
end
