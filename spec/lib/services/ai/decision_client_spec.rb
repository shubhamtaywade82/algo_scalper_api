# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Services::Ai::DecisionClient do
  # Request-policy specs for the System One client (POST /v1/systemone):
  #   * cloud sends the bearer token and no keep_alive; local sends keep_alive
  #   * a 429 is retried after the server's Retry-After, a 503 with backoff
  #   * 402 (no credits) is the server's final answer: no retry, its words kept
  #   * anything that is not a noul probability in 0..1 is an error
  #
  # HTTP is stubbed with WebMock against the real Net::HTTP call.

  URL = 'https://ollama.com/v1/systemone' # rubocop:disable RSpec/LeakyConstantDeclaration, Lint/ConstantDefinitionInBlock
  QUESTION = { # rubocop:disable RSpec/LeakyConstantDeclaration, Lint/ConstantDefinitionInBlock
    'type' => 'noul',
    'instructions' => 'Is the trade sound?',
    'criteria' => { 'true' => 'yes', 'false' => 'no' }
  }.freeze
  STATE = { 'instrument' => 'NIFTY', 'strike_distance_pct' => 0.41 }.freeze # rubocop:disable RSpec/LeakyConstantDeclaration, Lint/ConstantDefinitionInBlock

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

  def cloud_env(&)
    with_env('OLLAMA_DECISION_MODEL' => 'clef', 'OLLAMA_CLOUD_URL' => 'https://ollama.com',
             'OLLAMA_API_KEY' => 'secret', &)
  end

  def reply(noul)
    { model: 'clef', answers: { question: { type: 'noul', noul: noul } },
      usage: { input_tokens: 612, output_tokens: 0 } }.to_json
  end

  def record_sleeps(sleeps)
    # rspec-mocks yields the receiver as the block's first argument on
    # any_instance stubs: |_receiver, sec|.
    allow_any_instance_of(described_class).to receive(:sleep) { |_receiver, sec| sleeps << sec }
  end

  before do
    described_class.reset_instance!
    Services::Ai::OllamaClient.reset_instance!
  end

  it 'asks the cloud endpoint with a bearer token and no keep_alive' do
    cloud_env do
      stub_config(use_cloud: true)
      stub_request(:post, URL).to_return(status: 200, body: reply(0.91))

      score = described_class.instance.probability(state: STATE, question: QUESTION)

      expect(score.probability).to eq(0.91)
      expect(score.input_tokens).to eq(612)
      expect(WebMock).to have_requested(:post, URL)
        .with(headers: { 'Authorization' => 'Bearer secret', 'Content-Type' => 'application/json' },
              body: hash_including('model' => 'clef', 'state' => STATE, 'questions' => { 'question' => QUESTION }))
        .once
      expect(a_request(:post, URL).with { |req| JSON.parse(req.body).key?('keep_alive') }).not_to have_been_made
    end
  end

  it 'pins the model with keep_alive and sends no Authorization to a local daemon' do
    with_env('OLLAMA_DECISION_MODEL' => 'clef:cloud', 'OLLAMA_LOCAL_URL' => 'http://127.0.0.1:11434',
             'OLLAMA_API_KEY' => nil) do
      stub_config(use_cloud: false)
      local = 'http://127.0.0.1:11434/v1/systemone'
      stub_request(:post, local).to_return(status: 200, body: reply(0.8))

      expect(described_class.instance.probability(state: STATE, question: QUESTION).probability).to eq(0.8)

      expect(WebMock).to have_requested(:post, local)
        .with(body: hash_including('model' => 'clef:cloud',
                                   'keep_alive' => Services::Ai::OllamaClient::LOCAL_KEEP_ALIVE))
        .once
      expect(
        a_request(:post, local).with { |req| req.headers.keys.any? { |k| k.casecmp('Authorization').zero? } }
      ).not_to have_been_made
    end
  end

  it 'retries a 429 after the Retry-After delay the server asked for' do
    cloud_env do
      stub_config(use_cloud: true)
      stub_request(:post, URL)
        .to_return(status: 429, headers: { 'Retry-After' => '2' }, body: { error: 'rate limited' }.to_json)
        .to_return(status: 200, body: reply(0.4))
      sleeps = []
      record_sleeps(sleeps)

      score = described_class.instance.probability(state: STATE, question: QUESTION)

      expect(score.probability).to eq(0.4)
      expect(sleeps).to eq([2.0])
      expect(WebMock).to have_requested(:post, URL).twice
    end
  end

  it 'gives up after three attempts on a persistent 503 with exponential backoff' do
    cloud_env do
      stub_config(use_cloud: true)
      stub_request(:post, URL).to_return(status: 503, body: { error: 'overloaded' }.to_json)
      sleeps = []
      record_sleeps(sleeps)
      # CLOUD_RETRY_BASE is read at class load; stub it to observe the sequence.
      stub_const('Services::Ai::OllamaClient::CLOUD_RETRY_BASE', 0.01)

      expect { described_class.instance.ask(state: STATE, questions: { 'question' => QUESTION }) }
        .to raise_error(described_class::Error, /HTTP 503: overloaded/) { |e| expect(e.retryable).to be(true) }

      expect(sleeps).to eq([0.01, 0.02])
      expect(WebMock).to have_requested(:post, URL).times(3)
    end
  end

  it 'retries a dropped connection' do
    cloud_env do
      stub_config(use_cloud: true)
      stub_request(:post, URL).to_raise(Errno::ECONNRESET)
      sleeps = []
      record_sleeps(sleeps)

      expect { described_class.instance.ask(state: STATE, questions: { 'question' => QUESTION }) }
        .to raise_error(described_class::Error, /ECONNRESET/) { |e| expect(e.retryable).to be(true) }

      expect(sleeps.length).to eq(2)
      expect(WebMock).to have_requested(:post, URL).times(3)
    end
  end

  it 'does not retry a timeout: the attempt already spent its budget' do
    cloud_env do
      stub_config(use_cloud: true)
      stub_request(:post, URL).to_timeout
      record_sleeps([])

      expect { described_class.instance.ask(state: STATE, questions: { 'question' => QUESTION }) }
        .to raise_error(described_class::Error, /no reply within/) { |e| expect(e.retryable).to be(false) }

      expect(WebMock).to have_requested(:post, URL).once
    end
  end

  it 'fails fast on 402, keeping the server reason and never retrying' do
    cloud_env do
      stub_config(use_cloud: true)
      reason = "cloud model isn't included in the Free plan. Add usage credits or upgrade"
      stub_request(:post, URL).to_return(status: 402, body: { error: reason }.to_json)
      allow_any_instance_of(described_class).to receive(:sleep) { |*| raise 'must not retry a 402' }

      expect { described_class.instance.probability(state: STATE, question: QUESTION) }
        .to raise_error(described_class::Error, /HTTP 402: #{Regexp.escape(reason)}/) do |e|
          expect(e.status).to eq(402)
          expect(e.retryable).to be(false)
        end

      expect(WebMock).to have_requested(:post, URL).once
    end
  end

  it 'rejects a reply that is not a noul probability in 0..1' do
    cloud_env do
      stub_config(use_cloud: true)
      [
        { answers: { question: { type: 'noul', noul: 1.5 } } },
        { answers: {} },
        { answers: { question: { type: 'choice', choice: 'allow' } } }
      ].each do |body|
        stub_request(:post, URL).to_return(status: 200, body: body.to_json)
        expect { described_class.instance.probability(state: STATE, question: QUESTION) }
          .to raise_error(described_class::Error, /not a noul probability/)
      end

      stub_request(:post, URL).to_return(status: 200, body: '<html>gateway</html>')
      expect { described_class.instance.probability(state: STATE, question: QUESTION) }
        .to raise_error(described_class::Error, /not JSON/)
    end
  end
end
