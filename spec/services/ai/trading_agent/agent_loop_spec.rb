# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::TradingAgent::AgentLoop do
  let(:mock_client) { instance_double(Services::Ai::OllamaClient) }
  let(:agent) { described_class.new(model: 'test-model') }

  before do
    allow(Services::Ai::OllamaClient).to receive(:instance).and_return(mock_client)
    allow(mock_client).to receive(:chat_stream).and_return({ content: 'Hello', tool_calls: [] })
    allow(mock_client).to receive(:chat).and_return({ content: 'Hello', tool_calls: [] })
  end

  describe '#initialize' do
    it 'sets model from parameter' do
      expect(agent.model).to eq('test-model')
    end

    it 'defaults model from env' do
      allow(ENV).to receive(:fetch).with('AI_AGENT_MAX_ITERATIONS', '15').and_return('15')
      allow(ENV).to receive(:fetch).with('AI_AGENT_SYNTHESIS_TIMEOUT', '25').and_return('25')
      loop = described_class.new
      expect(loop.model).to be_present
    end
  end

  describe '#run_query' do
    context 'with simple text response' do
      it 'returns conversation messages' do
        allow(mock_client).to receive(:chat_stream).and_return({ content: 'NIFTY is bullish', tool_calls: [] })

        result = agent.run_query(query: 'What is NIFTY?')

        expect(result).to be_an(Array)
        expect(result.any? { |m| m[:content]&.include?('NIFTY') }).to be true
      end
    end

    context 'with tool calls' do
      it 'executes tools and returns analysis' do
        tool_response = {
          content: nil,
          tool_calls: [
            { 'function' => { 'name' => 'get_instrument', 'arguments' => '{"symbol":"NIFTY"}' } }
          ]
        }
        text_response = { content: 'NIFTY is at 23900', tool_calls: [] }

        call_count = 0
        allow(mock_client).to receive(:chat_stream).and_return(tool_response)
        allow(mock_client).to receive(:chat) do |**args|
          call_count += 1
          if args[:tools]
            # After tool execution, return text
            { content: 'Analysis complete', tool_calls: [] }
          else
            text_response
          end
        end

        allow(Ai::TradingAgent::ToolRegistry).to receive(:execute).and_return({
          symbol: 'Nifty 50', security_id: '13', ltp: 23_900
        })

        result = agent.run_query(query: 'NIFTY options?')

        expect(result).to be_an(Array)
      end
    end

    context 'with conversation history' do
      it 'includes previous messages' do
        allow(mock_client).to receive(:chat_stream).and_return({ content: 'Follow up', tool_calls: [] })

        conversation = [
          { role: 'user', content: 'Previous question' },
          { role: 'assistant', content: 'Previous answer' }
        ]

        result = agent.run_query(query: 'Follow up?', conversation: conversation)

        expect(result.length).to be >= 3 # system + 2 history + 1 new
      end
    end
  end

  describe '#run' do
    it 'resolves instrument and fetches data' do
      allow(Ai::TradingAgent::ToolRegistry).to receive(:execute).with('get_instrument', anything).and_return({
        security_id: '13', display_name: 'Nifty 50', exchange: 'nse', segment: 'index'
      })
      allow(Ai::TradingAgent::ToolRegistry).to receive(:execute).with('get_market_snapshot', anything).and_return({
        ltp: 23_900, indicators: { rsi: 55.0, adx: 25.0, supertrend: 'bullish' }
      })
      allow(Ai::TradingAgent::ToolRegistry).to receive(:execute).with('get_smc_analysis', anything).and_return({
        bias: 'bullish', confluence: 'aligned'
      })
      allow(Ai::TradingAgent::ToolRegistry).to receive(:execute).with('get_option_intelligence', anything).and_return({
        atm_strike: 23_900, days_to_expiry: 5
      })

      allow(mock_client).to receive(:chat_stream).and_return({ content: 'BUY NIFTY at 23900', tool_calls: [] })

      result = agent.run(symbol: 'NIFTY', timeframe: '15m')

      expect(result).to be_a(Hash)
      expect(result[:action]).to be_present
    end
  end

  describe 'normalize_response' do
    it 'passes through Hash responses' do
      response = { content: 'hello', tool_calls: [] }
      result = agent.send(:normalize_response, response)
      expect(result).to eq(response)
    end

    it 'passes through String responses' do
      response = 'hello'
      result = agent.send(:normalize_response, response)
      expect(result).to eq(response)
    end

    it 'returns empty Hash for nil' do
      result = agent.send(:normalize_response, nil)
      expect(result).to eq({})
    end

    it 'handles Ollama::Response objects' do
      ollama_response = double('Ollama::Response',
                               data: { 'message' => { 'content' => 'test', 'tool_calls' => [] } })
      allow(ollama_response).to receive(:respond_to?).with(:data).and_return(true)
      allow(ollama_response).to receive(:respond_to?).with(:message).and_return(false)

      result = agent.send(:normalize_response, ollama_response)
      expect(result[:content]).to eq('test')
    end
  end

  describe 'extract_response_content' do
    it 'extracts from Hash with content' do
      response = { content: 'hello', tool_calls: [] }
      result = agent.send(:extract_response_content, response)
      expect(result).to eq('hello')
    end

    it 'extracts thinking when content is empty' do
      response = { content: '', thinking: 'deep thought' }
      result = agent.send(:extract_response_content, response)
      expect(result).to eq('deep thought')
    end

    it 'returns nil for nil response' do
      result = agent.send(:extract_response_content, nil)
      expect(result).to be_nil
    end

    it 'returns String as-is' do
      result = agent.send(:extract_response_content, 'hello')
      expect(result).to eq('hello')
    end
  end

  describe 'format_tool_result' do
    it 'formats instrument results' do
      result = agent.send(:format_tool_result, 'get_instrument', {
        display_name: 'Nifty 50', security_id: '13', exchange: 'nse', segment: 'index'
      })
      expect(result).to include('Nifty 50')
      expect(result).to include('13')
    end

    it 'formats market snapshot results' do
      result = agent.send(:format_tool_result, 'get_market_snapshot', {
        ltp: 23_900, indicators: { rsi: 55.0 }
      })
      expect(result).to include('23900')
      expect(result).to include('55.0')
    end

    it 'formats option intelligence results' do
      result = agent.send(:format_tool_result, 'get_option_intelligence', {
        atm_strike: 23_900,
        days_to_expiry: 5,
        is_expiry_week: true,
        strikes: [{ strike: 23_900 }],
        atm_call: { ltp: 150, delta: 0.5, theta: -90, iv: 15.0 },
        atm_put: { ltp: 120, delta: -0.4, theta: -60, iv: 14.0 }
      })
      expect(result).to include('23900')
      expect(result).to include('5d')
    end

    it 'formats SMC results' do
      result = agent.send(:format_tool_result, 'get_smc_analysis', {
        bias: 'bullish', confluence: 'aligned'
      })
      expect(result).to include('bullish')
      expect(result).to include('aligned')
    end

    it 'handles nil results' do
      result = agent.send(:format_tool_result, 'get_instrument', nil)
      expect(result).to eq("\n")
    end
  end

  describe 'handle_tool_calls_loop' do
    it 'executes tools and builds messages' do
      initial_response = {
        content: nil,
        tool_calls: [
          { 'function' => { 'name' => 'get_instrument', 'arguments' => '{"symbol":"NIFTY"}' } }
        ]
      }

      allow(Ai::TradingAgent::ToolRegistry).to receive(:execute).and_return({
        display_name: 'Nifty 50', security_id: '13'
      })

      call_count = 0
      allow(mock_client).to receive(:chat) do |**args|
        call_count += 1
        { content: 'Analysis complete', tool_calls: [] }
      end

      messages = [
        { role: 'system', content: 'test' },
        { role: 'user', content: 'NIFTY?' }
      ]

      result = agent.send(:handle_tool_calls_loop, messages, initial_response)

      expect(result).to be_an(Array)
      expect(result.any? { |m| m[:content]&.include?('market data') }).to be true
    end

    it 'breaks when no tool calls' do
      response = { content: 'text', tool_calls: [] }
      messages = [{ role: 'user', content: 'test' }]

      result = agent.send(:handle_tool_calls_loop, messages, response)
      expect(result).to eq(messages)
    end

    it 'handles malformed tool call arguments' do
      initial_response = {
        content: nil,
        tool_calls: [
          { 'function' => { 'name' => 'get_instrument', 'arguments' => 'invalid json' } }
        ]
      }

      allow(mock_client).to receive(:chat).and_return({ content: 'done', tool_calls: [] })

      messages = [{ role: 'user', content: 'test' }]
      # Should not raise
      result = agent.send(:handle_tool_calls_loop, messages, initial_response)
      expect(result).to be_an(Array)
    end

    it 'handles nil function name' do
      initial_response = {
        content: nil,
        tool_calls: [
          { 'function' => { 'name' => nil, 'arguments' => '{}' } }
        ]
      }

      allow(mock_client).to receive(:chat).and_return({ content: 'done', tool_calls: [] })

      messages = [{ role: 'user', content: 'test' }]
      result = agent.send(:handle_tool_calls_loop, messages, initial_response)
      expect(result).to be_an(Array)
    end
  end

  describe 'map_timeframe' do
    it 'maps common timeframes' do
      expect(agent.send(:map_timeframe, '5m')).to eq('5')
      expect(agent.send(:map_timeframe, '15m')).to eq('15')
      expect(agent.send(:map_timeframe, '1h')).to eq('60')
      expect(agent.send(:map_timeframe, '1m')).to eq('1')
      expect(agent.send(:map_timeframe, '30m')).to eq('30')
    end

    it 'defaults to 15' do
      expect(agent.send(:map_timeframe, 'unknown')).to eq('15')
    end
  end

  describe 'resolve_intent' do
    it 'returns options_buying for indices' do
      result = agent.send(:resolve_intent, 'NIFTY', '15m')
      expect(result[:intent]).to eq(:options_buying)
    end

    it 'returns intraday for stocks' do
      result = agent.send(:resolve_intent, 'RELIANCE', '15m')
      expect(result[:intent]).to eq(:intraday)
    end

    it 'recognizes BANKNIFTY' do
      result = agent.send(:resolve_intent, 'BANKNIFTY', '15m')
      expect(result[:intent]).to eq(:options_buying)
    end

    it 'recognizes SENSEX' do
      result = agent.send(:resolve_intent, 'SENSEX', '15m')
      expect(result[:intent]).to eq(:options_buying)
    end
  end

  describe 'parse_trade_intent' do
    it 'extracts BUY action from JSON' do
      analysis = '{"action":"BUY","entry_price":100,"stop_loss":95,"take_profit":110}'
      result = agent.send(:parse_trade_intent, analysis, 'NIFTY', 100)
      expect(result[:action]).to eq('BUY')
      expect(result[:entry_price]).to eq(100.0)
    end

    it 'extracts SELL action' do
      analysis = '{"action":"SELL","confidence":0.8}'
      result = agent.send(:parse_trade_intent, analysis, 'NIFTY', 100)
      expect(result[:action]).to eq('SELL')
    end

    it 'returns HOLD for non-JSON' do
      result = agent.send(:parse_trade_intent, 'Buy NIFTY at 100', 'NIFTY', 100)
      expect(result[:action]).to eq('HOLD')
    end

    it 'returns HOLD for nil' do
      result = agent.send(:parse_trade_intent, nil, 'NIFTY', 100)
      expect(result[:action]).to eq('HOLD')
    end
  end

  describe 'truncate_tool_result' do
    it 'returns {} for nil' do
      expect(agent.send(:truncate_tool_result, nil)).to eq('{}')
    end

    it 'returns JSON for small results' do
      result = agent.send(:truncate_tool_result, { ltp: 100 })
      expect(result).to include('100')
    end

    it 'truncates large results' do
      large = { data: 'x' * 5000 }
      result = agent.send(:truncate_tool_result, large)
      expect(result).to include('[truncated]')
    end
  end
end
