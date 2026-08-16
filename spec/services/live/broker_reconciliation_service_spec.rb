# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Live::BrokerReconciliationService do
  subject(:service) { described_class.new(client: mock_client) }

  let(:mock_client) { double('DhanHQClient') }

  before do
    allow(AlgoConfig).to receive(:fetch).and_return({ paper_trading: { enabled: false } })
  end

  describe '#reconcile!' do
    context 'when broker returns matching data' do
      before do
        allow(mock_client).to receive(:orders).and_return({ data: [] })
        allow(mock_client).to receive(:positions).and_return({ data: [] })
        allow(mock_client).to receive(:fund_limit).and_return({ data: { available_margin: 100_000 } })
        allow(Ledger::WalletReader).to receive(:snapshot).and_return({ cash: 100_000 })
      end

      it 'creates a passed reconciliation run' do
        run = service.reconcile!
        expect(run.status).to eq('passed')
        expect(run.discrepancies_found).to eq(0)
      end
    end

    context 'when in paper mode' do
      before do
        allow(AlgoConfig).to receive(:fetch).and_return({ paper_trading: { enabled: true } })
      end

      it 'skips broker checks and passes' do
        run = service.reconcile!
        expect(run.status).to eq('passed')
        expect(run.orders_checked).to eq(0)
      end
    end

    context 'when critical discrepancy found' do
      before do
        allow(mock_client).to receive(:orders).and_return({ data: [] })
        allow(mock_client).to receive(:positions).and_return({ data: [] })
        allow(mock_client).to receive(:fund_limit).and_return({ data: { available_margin: 500_000 } })
        allow(Ledger::WalletReader).to receive(:snapshot).and_return({ cash: 100_000 })
      end

      it 'trips the circuit breaker' do
        expect(Risk::CircuitBreaker.instance).to receive(:trip!)
        run = service.reconcile!
        expect(run.status).to eq('failed')
        expect(run.halted_trading).to be(true)
      end
    end
  end
end
