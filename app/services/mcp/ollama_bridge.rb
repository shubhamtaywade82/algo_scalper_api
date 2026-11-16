# frozen_string_literal: true

require 'net/http'

module MCP
  # Answers a question with a local Ollama model that calls this app's MCP tools
  # over Streamable HTTP (bin/mcp). Talks to the MCP server, never to services
  # directly, so it sees exactly what Cursor/Claude would.
  class OllamaBridge
    class Error < StandardError; end

    DEFAULT_URL = 'http://127.0.0.1:62770/'
    DEFAULT_MODEL = 'openbmb/minicpm5-2b'
    PROTOCOL_VERSION = '2025-11-25'
    # Small models loop on tool calls; cap rounds and force a plain answer after.
    MAX_TOOL_ROUNDS = 3
    SYSTEM_PROMPT = <<~PROMPT
      You analyse an automated Indian index-options trading system using the provided tools.
      Always call a tool before answering. Quote numbers exactly as returned.
      A status of unavailable, stale or last_session means the value is not live; say so.
      You cannot place or cancel trades. Answer in a few short sentences.
    PROMPT

    def initialize(token: nil, url: DEFAULT_URL, model: DEFAULT_MODEL, llm: Services::Ai::OllamaClient.instance)
      @uri = URI(url)
      @token = token
      @model = model
      @llm = llm
      @request_id = 0
    end

    def ask(question)
      open_session!
      messages = [{ role: 'system', content: SYSTEM_PROMPT }, { role: 'user', content: question }]
      tools = ollama_tools

      MAX_TOOL_ROUNDS.times do
        reply = chat(messages, tools)
        return reply[:content].to_s if reply[:tool_calls].blank?

        calls = reply[:tool_calls].map { |call| with_parsed_arguments(call) }
        messages << { role: 'assistant', content: reply[:content].to_s, tool_calls: calls }
        calls.each { |call| messages << tool_message(call) }
      end
      chat(messages, nil)[:content].to_s
    end

    private

    def chat(messages, tools)
      reply = @llm.chat(messages: messages, model: @model, temperature: 0.1, tools: tools)
      raise Error, "Ollama returned no reply (model #{@model})" if reply.nil?

      reply.is_a?(Hash) ? reply : { content: reply, tool_calls: [] }
    end

    # OllamaClient hands arguments back as a JSON string, but Ollama rejects a string
    # when the assistant turn is replayed; it wants the object.
    def with_parsed_arguments(call)
      args = JSON.parse(call.dig('function', 'arguments').presence || '{}')
      call.deep_merge('function' => { 'arguments' => args.is_a?(Hash) ? args : {} })
    rescue JSON::ParserError
      call.deep_merge('function' => { 'arguments' => {} })
    end

    def tool_message(call)
      name = call.dig('function', 'name')
      result = rpc('tools/call', name: name, arguments: call.dig('function', 'arguments'))
      text = Array(result['content']).filter_map { |c| c['text'] }.join("\n")
      { role: 'tool', name: name, content: text }
    end

    def ollama_tools
      rpc('tools/list')['tools'].map do |tool|
        { type: 'function',
          function: { name: tool['name'], description: tool['description'], parameters: tool['inputSchema'] } }
      end
    end

    def open_session!
      response = post(method: 'initialize', params: {
                        protocolVersion: PROTOCOL_VERSION, capabilities: {},
                        clientInfo: { name: 'algo-scalper-ollama-bridge', version: '1.0' }
                      })
      @session_id = response['Mcp-Session-Id'] or raise Error, 'MCP server returned no session id'
      post(method: 'notifications/initialized', params: {}, notification: true)
    end

    def rpc(method, params = {})
      body = JSON.parse(post(method: method, params: params).body)
      raise Error, "MCP #{method} failed: #{body['error']['message']}" if body['error']

      body['result']
    end

    def post(method:, params:, notification: false)
      payload = { jsonrpc: '2.0', method: method, params: params }
      payload[:id] = (@request_id += 1) unless notification
      response = Net::HTTP.post(@uri, payload.to_json, headers)
      raise Error, "MCP #{method} HTTP #{response.code}: #{response.body.to_s[0, 200]}" unless response.is_a?(Net::HTTPSuccess)

      response
    end

    def headers
      {
        'Content-Type' => 'application/json',
        'Accept' => 'application/json, text/event-stream',
        'Authorization' => ("Bearer #{@token}" if @token.present?),
        'MCP-Protocol-Version' => PROTOCOL_VERSION,
        'Mcp-Session-Id' => @session_id
      }.compact
    end
  end
end
