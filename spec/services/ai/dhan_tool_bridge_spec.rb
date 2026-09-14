# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::DhanToolBridge do
  # The dhanhq-mcp adapter gem is PATH-installed on the operator workstation
  # and deliberately not in this repo's Gemfile, so in CI (and on any machine
  # without the adapter) the bridge runs in its degraded mode: no tools are
  # advertised and every call returns a structured adapter_unavailable failure
  # instead of raising NameError.
  describe '.tools_for_ollama' do
    it 'returns an empty list while the dhanhq-mcp adapter is not installed' do
      expect(described_class.adapter_available?).to be(false)

      expect(described_class.tools_for_ollama).to eq([])
    end
  end

  describe '.call' do
    before { described_class.reset! }

    it 'returns a structured adapter_unavailable failure for a known portfolio tool' do
      result = described_class.call('portfolio.funds')

      expect(result).to include(
        error: 'adapter_unavailable',
        tool_name: 'portfolio.funds',
        message: 'dhanhq-mcp adapter gem is not installed'
      )
    end

    it 'returns the same adapter_unavailable failure for unknown tools' do
      result = described_class.call('unknown.tool')

      expect(result).to include(
        error: 'adapter_unavailable',
        tool_name: 'unknown.tool',
        message: 'dhanhq-mcp adapter gem is not installed'
      )
    end

    it 'reset! clears memoized adapter state and the availability guard stays false' do
      expect(described_class.adapter_available?).to be(false)

      expect { described_class.reset! }.not_to raise_error
      expect(described_class.instance_variable_get(:@context)).to be_nil
      expect(described_class.instance_variable_get(:@dhanhq_client)).to be_nil
    end
  end
end
