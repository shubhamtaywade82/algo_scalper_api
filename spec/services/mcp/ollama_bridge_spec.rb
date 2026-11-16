# frozen_string_literal: true

require 'rails_helper'

RSpec.describe MCP::OllamaBridge do
  let(:url) { 'http://127.0.0.1:62770/' }
  let(:tool_call) { { 'id' => '1', 'type' => 'function', 'function' => { 'name' => 'get_risk_status', 'arguments' => '{}' } } }
  let(:llm) { instance_double(Services::Ai::OllamaClient) }

  def rpc_reply(request)
    body = JSON.parse(request.body)
    result = case body['method']
             when 'tools/list' then { tools: [{ name: 'get_risk_status', description: 'risk', inputSchema: { type: 'object' } }] }
             when 'tools/call' then { content: [{ type: 'text', text: '{"tripped":false}' }] }
             else {}
             end
    { body: { jsonrpc: '2.0', id: body['id'], result: result }.to_json, headers: { 'Mcp-Session-Id' => 'abc' } }
  end

  before { stub_request(:post, url).to_return { |request| rpc_reply(request) } }

  it 'feeds MCP tool results back to the model and returns its answer' do
    allow(llm).to receive(:chat).and_return({ content: '', tool_calls: [tool_call] }, { content: 'Breaker armed.', tool_calls: [] })

    answer = described_class.new(token: 't', url: url, llm: llm).ask('breaker?')

    expect(answer).to eq('Breaker armed.')
    expect(llm).to have_received(:chat).with(hash_including(messages: array_including(
      hash_including(role: 'tool', content: '{"tripped":false}')
    ))).at_least(:once)
  end

  it 'stops calling tools after the round cap and asks for a plain answer' do
    allow(llm).to receive(:chat) { |**kw| kw[:tools] ? { content: '', tool_calls: [tool_call] } : { content: 'done', tool_calls: [] } }

    expect(described_class.new(token: 't', url: url, llm: llm).ask('loop')).to eq('done')
    expect(llm).to have_received(:chat).exactly(described_class::MAX_TOOL_ROUNDS + 1).times
  end
end
