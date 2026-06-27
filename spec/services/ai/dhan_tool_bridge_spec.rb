# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::DhanToolBridge do
  describe '.tools_for_ollama' do
    it 'returns a list of function tools' do
      tools = described_class.tools_for_ollama

      expect(tools).to be_an(Array)
      expect(tools.length).to be_positive
      expect(tools.first).to include(
        type: 'function',
        function: be_a(Hash)
      )
    end
  end

  describe '.call' do
    before { described_class.reset! }

    it 'dispatches a known portfolio tool without raising' do
      result = described_class.call('portfolio.funds')
      expect(result).to be_a(Hash)
    end

    it 'returns a structured failure for unknown tools' do
      result = described_class.call('unknown.tool')
      expect(result).to include(
        error: 'unknown_tool',
        tool_name: 'unknown.tool'
      )
    end

    it 'normalizes exceptions into a result hash' do
      bad_args = { 'exchange_segment' => 'IDX_I', 'symbol' => 'INVALID_SYMBOL' }
      allow(Dhanhq::Mcp::Router)
        .to receive(:call)
        .and_raise(StandardError, 'boom')

      result = described_class.call('instrument.find', bad_args)
      expect(result).to include(
        error: 'tool_call_failed',
        tool_name: 'instrument.find'
      )
    end
  end
end
