# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Services::Ai::OllamaClient do
  def ollama_spec_env_keys
    %w[
      OLLAMA_LOCAL_URL OLLAMA_HOST_URL OLLAMA_BASE_URL OLLAMA_CLOUD_URL OLLAMA_API_KEY
    ]
  end

  def with_env(overrides)
    saved = ollama_spec_env_keys.index_with { |k| ENV.fetch(k, nil) }
    overrides.each do |k, v|
      if v.nil?
        ENV.delete(k)
      else
        ENV[k] = v
      end
    end
    yield
  ensure
    saved.each do |k, v|
      if v.nil?
        ENV.delete(k)
      else
        ENV[k] = v
      end
    end
  end

  let(:fake_ollama) { instance_double(Ollama::Client) }

  before do
    described_class.reset_instance!
    allow(Ollama::Client).to receive(:new).and_return(fake_ollama)
  end

  describe 'local vs cloud (ai.ollama_use_cloud)' do
    it 'uses local URL chain when ollama_use_cloud is false' do
      with_env(
        'OLLAMA_LOCAL_URL' => nil,
        'OLLAMA_HOST_URL' => nil,
        'OLLAMA_BASE_URL' => 'http://192.168.1.10:11434',
        'OLLAMA_CLOUD_URL' => nil,
        'OLLAMA_API_KEY' => nil
      ) do
        allow(AlgoConfig).to receive(:fetch).and_return(
          { ai: { enabled: true, ollama_use_cloud: false } }
        )

        client = described_class.new
        expect(client.enabled?).to be true
        expect(client.ollama_base_url).to eq('http://192.168.1.10:11434')
      end
    end

    it 'uses cloud URL and requires API key when ollama_use_cloud is true' do
      with_env(
        'OLLAMA_CLOUD_URL' => 'https://example-ollama.test',
        'OLLAMA_BASE_URL' => 'http://ignored.local:11434',
        'OLLAMA_API_KEY' => 'secret'
      ) do
        allow(AlgoConfig).to receive(:fetch).and_return(
          { ai: { enabled: true, ollama_use_cloud: true } }
        )

        client = described_class.new
        expect(client.enabled?).to be true
        expect(client.ollama_base_url).to eq('https://example-ollama.test')
      end
    end

    it 'stays disabled when cloud mode and API key is blank' do
      with_env(
        'OLLAMA_CLOUD_URL' => 'https://example-ollama.test',
        'OLLAMA_API_KEY' => nil
      ) do
        allow(AlgoConfig).to receive(:fetch).and_return(
          { ai: { enabled: true, ollama_use_cloud: true } }
        )

        client = described_class.new
        expect(client.enabled?).to be false
        expect(client.client).to be_nil
      end
    end
  end
end
