# frozen_string_literal: true

require 'rails_helper'

# Exercises the RubyLLM 2.x agents end to end over HTTP (Ollama's
# OpenAI-compatible /v1/chat/completions, stubbed with WebMock).
RSpec.describe ApplicationAgent do
  let(:endpoint) { "#{LLMSettings.api_base}/chat/completions" }
  let(:analysis) do
    { bias: 'BULLISH', trend_strength: 'MODERATE', key_zones: 'Demand OB below', rationale: 'Higher highs' }
  end

  def completion(content: nil, tool_calls: nil, finish_reason: 'stop')
    message = { role: 'assistant', content: content }
    message[:tool_calls] = tool_calls if tool_calls
    {
      status: 200,
      headers: { 'Content-Type' => 'application/json' },
      body: {
        id: 'chatcmpl-1', object: 'chat.completion', model: LLMSettings.default_model,
        choices: [{ index: 0, message: message, finish_reason: finish_reason }],
        usage: { prompt_tokens: 10, completion_tokens: 5, total_tokens: 15 }
      }.to_json
    }
  end

  def tool_call(name, arguments)
    [{ id: 'call_1', type: 'function', function: { name: name, arguments: arguments.to_json } }]
  end

  describe 'MarketAnalystAgent.call' do
    it 'runs the tool loop and returns the parsed structured output' do
      requests = []
      stub_request(:post, endpoint)
        .to_return(completion(tool_calls: tool_call('get_market_context', index_key: 'NIFTY'), finish_reason: 'tool_calls'),
                   completion(content: analysis.to_json))
        .with { |req| requests << JSON.parse(req.body) }
      allow(IndexConfigLoader).to receive(:load_indices).and_return([]) # tool reports "Unknown index" without DB/broker access

      result = MarketAnalystAgent.call(index_key: 'NIFTY')

      expect(result).to eq(analysis.stringify_keys)
      first = requests.first
      expect(first['model']).to eq(LLMSettings.default_model)
      expect(first['messages'].first).to include('role' => 'system')
      expect(first['messages'].first['content']).to include('Market Analyst Agent')
      expect(first['messages'].last).to include('role' => 'user',
                                                'content' => 'Analyze the market state for NIFTY on a 5-minute interval.')
      expect(first['tools'].map { |t| t.dig('function', 'name') }).to eq(['get_market_context'])
      expect(first.to_json).to include('trend_strength') # JSON schema sent for structured output

      tool_result = requests.last['messages'].find { |m| m['role'] == 'tool' }
      expect(tool_result['content']).to include('Unknown index: NIFTY')
    end

    it 'raises on a missing required input before any request' do
      expect { RiskAgent.call }.to raise_error(ArgumentError, /missing inputs strategy_details/)
      expect(a_request(:post, endpoint)).not_to have_been_made
    end

    it 'raises InvalidResponseError when the model ignores the schema' do
      stub_request(:post, endpoint).to_return(completion(content: 'Market looks bullish to me.'))
      expect { StrategyAgent.call(index_key: 'NIFTY', market_analysis: 'x') }
        .to raise_error(ApplicationAgent::InvalidResponseError, /not valid JSON/)
    end

    it 'surfaces provider errors as RubyLLM errors' do
      allow(RubyLLM.config).to receive(:max_retries).and_return(0)
      stub_request(:post, endpoint).to_return(status: 500, body: { error: { message: 'model crashed' } }.to_json,
                                              headers: { 'Content-Type' => 'application/json' })
      expect { ResearchAgent.call }.to raise_error(RubyLLM::Error)
    end
  end

  it 'declares inputs, tools and schemas on every agent' do
    expect(MarketAnalystAgent.inputs).to eq(%i[index_key interval])
    expect(OptionSelectorAgent.tools).to eq([GetOptionChainTool])
    expect(StrategyAgent.tools).to eq([])
    expect(described_class.descendants.map(&:name))
      .to contain_exactly('MarketAnalystAgent', 'OptionSelectorAgent', 'ResearchAgent', 'RiskAgent', 'StrategyAgent')
    described_class.descendants.each { |agent| expect(agent.user_prompt).to be_present }
  end
end
