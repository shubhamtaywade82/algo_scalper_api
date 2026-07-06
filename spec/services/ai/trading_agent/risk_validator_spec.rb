# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::TradingAgent::RiskValidator do
  describe '.validate' do
    let(:equity) { 100_000.0 }

    context 'with valid BUY signal' do
      let(:signal) do
        {
          action: 'BUY',
          entry_price: 100.0,
          stop_loss: 95.0,
          take_profit: 110.0,
          risk_percent: 1.5
        }
      end

      it 'approves the trade' do
        result = described_class.validate(signal, equity: equity)
        expect(result.approved).to be(true)
        expect(result.action).to eq('BUY')
      end

      it 'calculates correct R:R ratio' do
        result = described_class.validate(signal, equity: equity)
        expect(result.risk_checks[:rr_ratio]).to eq(2.0)
      end
    end

    context 'with invalid R:R ratio' do
      let(:signal) do
        {
          action: 'BUY',
          entry_price: 100.0,
          stop_loss: 95.0,
          take_profit: 102.0,
          risk_percent: 1.5
        }
      end

      it 'rejects the trade' do
        result = described_class.validate(signal, equity: equity)
        expect(result.approved).to be(false)
        expect(result.action).to eq('HOLD')
      end
    end

    context 'with wrong stop direction for BUY' do
      let(:signal) do
        {
          action: 'BUY',
          entry_price: 100.0,
          stop_loss: 105.0,
          take_profit: 115.0,
          risk_percent: 1.5
        }
      end

      it 'rejects the trade' do
        result = described_class.validate(signal, equity: equity)
        expect(result.approved).to be(false)
      end
    end

    context 'with valid SELL signal' do
      let(:signal) do
        {
          action: 'SELL',
          entry_price: 100.0,
          stop_loss: 105.0,
          take_profit: 90.0,
          risk_percent: 1.5
        }
      end

      it 'approves the trade' do
        result = described_class.validate(signal, equity: equity)
        expect(result.approved).to be(true)
        expect(result.action).to eq('SELL')
      end
    end

    context 'with stale data' do
      let(:signal) do
        {
          action: 'BUY',
          entry_price: 100.0,
          stop_loss: 95.0,
          take_profit: 110.0,
          risk_percent: 1.5
        }
      end

      it 'rejects when data is older than 5 minutes' do
        result = described_class.validate(
          signal,
          equity: equity,
          data_timestamp: 6.minutes.ago
        )
        expect(result.approved).to be(false)
        expect(result.risk_checks[:data_fresh]).to be(false)
      end
    end
  end
end
