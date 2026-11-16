# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::MCP endpoints' do
  let(:bridge) do
    instance_double(MCP::OllamaBridge, model: 'openbmb/minicpm5-2b', tools_used: ['get_risk_status'],
                                       list_tools: [{ 'name' => 'get_risk_status', 'description' => 'risk' }])
  end

  before { allow(MCP::OllamaBridge).to receive(:new).and_return(bridge) }

  it 'lists the MCP tools' do
    get '/api/mcp/tools'
    expect(response.parsed_body).to include('online' => true, 'tools' => [hash_including('name' => 'get_risk_status')])
  end

  it 'reports the server offline instead of erroring when bin/mcp is down' do
    allow(bridge).to receive(:list_tools).and_raise(Errno::ECONNREFUSED)
    get '/api/mcp/tools'
    expect(response.parsed_body).to include('online' => false, 'tools' => [])
  end

  it 'creates a tool call and returns parsed JSON' do
    allow(bridge).to receive(:call_tool).with('get_risk_status', { 'index' => 'NIFTY' }).and_return('{"tripped":false}')
    post '/api/mcp/tools/get_risk_status/calls', params: { arguments: { index: 'NIFTY' } }, as: :json
    expect(response).to have_http_status(:created)
    expect(response.parsed_body['result']).to eq('tripped' => false)
  end

  it 'answers a question with the tools the model used' do
    allow(bridge).to receive(:ask).with('breaker?').and_return('Not tripped.')
    post '/api/mcp/questions', params: { question: 'breaker?' }, as: :json
    expect(response.parsed_body).to include('answer' => 'Not tripped.', 'tools_used' => ['get_risk_status'])
  end

  it 'rejects an over-long question' do
    post '/api/mcp/questions', params: { question: 'x' * 501 }, as: :json
    expect(response).to have_http_status(:unprocessable_content)
  end
end
