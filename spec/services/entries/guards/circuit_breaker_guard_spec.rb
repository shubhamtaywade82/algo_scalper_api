# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Entries::Guards::CircuitBreakerGuard do
  describe '.call' do
    let(:context) { {} }

    before do
      allow(Risk::CircuitBreaker.instance).to receive(:tripped?).and_return(false)
    end

    context 'when circuit breaker is not tripped' do
      it 'allows entry' do
        result = described_class.call(context)
        expect(result).to eq(Entries::EntryGuardPipeline::PASS)
      end
    end

    context 'when circuit breaker is tripped' do
      before do
        allow(Risk::CircuitBreaker.instance).to receive_messages(tripped?: true, status: { tripped: true, reason: 'max_daily_drawdown', at: '2025-01-01 10:00:00' })
      end

      it 'blocks entry' do
        result = described_class.call(context)
        expect(result).to include(blocked: /circuit breaker tripped/)
        expect(result[:blocked]).to include('max_daily_drawdown')
      end
    end
  end
end
