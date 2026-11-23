# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::AlphaGate do
  # The gate's two model paths and what each does when the model does not
  # answer. Both fail OPEN (allow the trade), as the gate always has:
  #   * OLLAMA_DECISION_MODEL: a probability against OLLAMA_DECISION_ALLOW_THRESHOLD
  #   * chat (default): ALLOW / BLOCK parsed from a one-word reply
  #
  # The decision model is stubbed with WebMock; the chat gem client is doubled,
  # as in spec/lib/services/ai/ollama_client_cloud_spec.rb.

  URL = 'https://ollama.com/v1/systemone' # rubocop:disable RSpec/LeakyConstantDeclaration, Lint/ConstantDefinitionInBlock

  let(:signal) do
    { index_key: 'nifty', direction: 'bullish', alpha_source: 'momentum_breakout',
      underlying_ltp: 24_500.5, strike: 24_600, stop_loss: 24_450.0, target: 24_600.0,
      confidence: 0.72 }
  end

  let(:gate_config) do
    { ai: { enabled: true, ollama_use_cloud: true }, alpha_strategies: { ai_gate: { enabled: true } } }
  end

  def with_env(overrides)
    keys = overrides.keys
    saved = keys.index_with { |k| ENV.fetch(k, nil) }
    overrides.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
    yield
  ensure
    saved.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
  end

  def stub_decision(noul)
    stub_request(:post, URL).to_return(
      status: 200,
      body: { model: 'clef', answers: { question: { type: 'noul', noul: noul } },
              usage: { input_tokens: 612, output_tokens: 0 } }.to_json
    )
  end

  # A decision model is configured unless a test says otherwise.
  around do |example|
    with_env('OLLAMA_DECISION_MODEL' => 'clef', 'OLLAMA_DECISION_ALLOW_THRESHOLD' => nil,
             'OLLAMA_CLOUD_URL' => 'https://ollama.com', 'OLLAMA_API_KEY' => 'secret', &example)
  end

  before do
    Services::Ai::DecisionClient.reset_instance!
    Services::Ai::OllamaClient.reset_instance!
    allow(AlgoConfig).to receive(:fetch).and_return(gate_config)
  end

  describe 'when the gate is switched off in config' do
    let(:gate_config) do
      { ai: { enabled: true, ollama_use_cloud: true }, alpha_strategies: { ai_gate: { enabled: false } } }
    end

    it 'allows the trade without consulting any model' do
      expect(Services::Ai::DecisionClient).not_to receive(:instance)

      expect(described_class.approve?(signal)).to be(true)
    end
  end

  describe 'with a decision model (OLLAMA_DECISION_MODEL)' do
    it 'allows a trade the model scores as sound and sends it the computed distances' do
      stub_decision(0.91)

      expect(described_class.approve?(signal)).to be(true)

      expect(WebMock).to have_requested(:post, URL).with { |req|
        state = JSON.parse(req.body)['state']
        state['instrument'] == 'NIFTY' && state['option_side'] == 'BUY' &&
          state['engine_confidence_pct'] == 72.0 && state['index_price'] == 24_500.5 &&
          state['stop_loss_distance_pct'] == 0.21 && state['strike_distance_pct'] == 0.41 &&
          state['target_distance_pct'] == 0.41 && state['time_ist'].match?(/\A\d{2}:\d{2}\z/)
      }.once
    end

    it 'blocks a trade the model scores below the default threshold' do
      stub_decision(0.3)

      expect(described_class.approve?(signal)).to be(false)
    end

    it 'reads the threshold from OLLAMA_DECISION_ALLOW_THRESHOLD' do
      with_env('OLLAMA_DECISION_ALLOW_THRESHOLD' => '0.95') do
        stub_decision(0.9)
        expect(described_class.approve?(signal)).to be(false)
      end

      with_env('OLLAMA_DECISION_ALLOW_THRESHOLD' => '0.2') do
        stub_decision(0.3)
        expect(described_class.approve?(signal)).to be(true)
      end
    end

    it 'falls back to the default threshold when the value is not in (0, 1]' do
      with_env('OLLAMA_DECISION_ALLOW_THRESHOLD' => '1.5') do
        expect(described_class.allow_threshold).to eq(0.5)
      end
      with_env('OLLAMA_DECISION_ALLOW_THRESHOLD' => '0') do
        expect(described_class.allow_threshold).to eq(0.5)
      end

      expect(described_class.allow_threshold).to eq(0.5)
    end

    it 'omits a distance the signal has no level for' do
      signal[:stop_loss] = nil

      state = described_class.decision_state(signal)

      expect(state).not_to have_key('stop_loss_distance_pct')
      expect(state['strike_distance_pct']).to eq(0.41)
    end

    it 'fails open when the model call is refused (402: no credits)' do
      stub_request(:post, URL).to_return(status: 402, body: { error: 'Add usage credits or upgrade' }.to_json)

      expect(described_class.approve?(signal)).to be(true)
    end

    it 'fails open when the model does not answer in time' do
      allow_any_instance_of(Services::Ai::DecisionClient).to receive(:probability).and_raise(Timeout::Error)

      expect(described_class.approve?(signal)).to be(true)
    end

    it 'fails open without a request when Ollama is not usable (no key on the cloud)' do
      with_env('OLLAMA_API_KEY' => nil) do
        expect(described_class.approve?(signal)).to be(true)
        expect(WebMock).not_to have_requested(:post, URL)
      end
    end
  end

  describe 'with the chat model' do
    around do |example|
      with_env('OLLAMA_DECISION_MODEL' => nil, &example)
    end

    def chat_returns(content)
      # Doubles the shape OllamaClient#chat expects: content + a nil message
      # (message&.tool_calls must nil-path, so message cannot be a String).
      fake = instance_double(Ollama::Client)
      allow(Ollama::Client).to receive(:new).and_return(fake)
      allow(fake).to receive(:chat).and_return(Struct.new(:content, :message).new(content, nil))
    end

    it 'blocks on BLOCK and allows on ALLOW' do
      chat_returns('BLOCK')
      expect(described_class.approve?(signal)).to be(false)

      Services::Ai::OllamaClient.reset_instance!
      chat_returns('ALLOW')
      expect(described_class.approve?(signal)).to be(true)
    end

    it 'fails open when the chat returns nothing' do
      chat_returns(nil)

      expect(described_class.approve?(signal)).to be(true)
    end

    it 'fails open when the chat does not answer in time' do
      allow_any_instance_of(Services::Ai::OllamaClient).to receive(:chat).and_raise(Timeout::Error)

      expect(described_class.approve?(signal)).to be(true)
    end
  end
end
