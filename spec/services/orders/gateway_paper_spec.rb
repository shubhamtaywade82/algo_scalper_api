# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Orders::GatewayPaper do
  let(:gateway) { described_class.new }
  let(:tracker) do
    create(:position_tracker, :option_position,
           status: 'active',
           segment: 'NSE_FNO',
           security_id: '55111',
           order_no: 'TEST123',
           entry_price: 100.0)
  end

  before do
    allow(Live::TickCache).to receive(:ltp).and_return(101.5)
    allow(AlgoConfig).to receive(:fetch).and_return({ paper_trading: { balance: 100_000 } })
  end

  describe '#exit_market' do
    it 'returns success hash with exit_price from LTP' do
      result = gateway.exit_market(tracker)

      expect(result).to include(
        success: true,
        exit_price: BigDecimal('101.5'),
        order_id: "PAPER-EXIT-#{tracker.id}",
        client_order_id: "PAPER-EXIT-#{tracker.id}",
        status: :accepted,
        paper: true
      )
    end

    it 'uses entry_price as fallback when LTP is nil' do
      allow(Live::TickCache).to receive(:ltp).and_return(nil)

      result = gateway.exit_market(tracker)

      expect(result).to include(success: true, exit_price: BigDecimal('100.0'))
    end

    it 'uses entry_price as fallback when LTP raises error' do
      allow(Live::TickCache).to receive(:ltp).and_raise(StandardError.new('Cache error'))

      result = gateway.exit_market(tracker)

      expect(result).to include(success: true, exit_price: BigDecimal('100.0'))
    end

    it 'uses provided client_order_id as order identity' do
      result = gateway.exit_market(tracker, client_order_id: 'COID-123')

      expect(result).to include(order_id: 'COID-123', client_order_id: 'COID-123', status: :accepted)
    end

    it 'does not update tracker directly' do
      expect(tracker).not_to receive(:mark_exited!)

      gateway.exit_market(tracker)

      tracker.reload
      expect(tracker.status).to eq('active')
    end

    it 'returns BigDecimal for exit_price' do
      result = gateway.exit_market(tracker)

      expect(result[:exit_price]).to be_a(BigDecimal)
    end
  end

  describe '#place_market' do
    it 'returns a simulated broker acknowledgement without persisting tracker' do
      expect do
        result = gateway.place_market(
          side: 'buy',
          segment: 'NSE_FNO',
          security_id: '55111',
          qty: 50,
          meta: { price: 100.5, symbol: 'NIFTY24JAN20000CE' }
        )

        expect(result).to include(success: true, paper: true)
        expect(result[:order_id]).to start_with('PAPER-')
      end.not_to change(PositionTracker, :count)
    end

    it 'uses provided client_order_id when present' do
      result = gateway.place_market(
        side: 'buy',
        segment: 'NSE_FNO',
        security_id: '55111',
        qty: 50,
        meta: { client_order_id: 'ENTRY-COID-123' }
      )

      expect(result).to include(success: true, order_id: 'ENTRY-COID-123', paper: true)
    end

    it 'logs errors when simulation fails' do
      allow(SecureRandom).to receive(:hex).and_raise(StandardError.new('RNG error'))
      expect(Rails.logger).to receive(:error).with(/GatewayPaper.*place_market failed/)

      result = gateway.place_market(
        side: 'buy',
        segment: 'NSE_FNO',
        security_id: '55111',
        qty: 50
      )

      expect(result).to include(success: false, paper: true)
      expect(result[:error]).to be_present
    end
  end

  describe '#position' do
    context 'when tracker exists' do
      it 'returns position hash with consistent format' do
        tracker.update!(quantity: 50, avg_price: 100.5, side: 'BUY', symbol: 'NIFTY24JAN20000CE')

        result = gateway.position(segment: 'NSE_FNO', security_id: '55111')

        expect(result).to eq(
          qty: 50,
          avg_price: 100.5,
          product_type: nil,
          exchange_segment: 'NSE_FNO',
          position_type: 'LONG',
          trading_symbol: 'NIFTY24JAN20000CE',
          status: 'active'
        )
      end

      it 'returns SHORT position_type for SELL side' do
        tracker.update!(side: 'SELL')

        result = gateway.position(segment: 'NSE_FNO', security_id: '55111')

        expect(result[:position_type]).to eq('SHORT')
      end

      it 'returns LONG position_type for BUY side' do
        tracker.update!(side: 'BUY')

        result = gateway.position(segment: 'NSE_FNO', security_id: '55111')

        expect(result[:position_type]).to eq('LONG')
      end
    end

    context 'when tracker does not exist' do
      it 'returns nil' do
        result = gateway.position(segment: 'NSE_FNO', security_id: '99999')

        expect(result).to be_nil
      end
    end
  end

  describe '#wallet_snapshot' do
    it 'returns wallet hash with configured balance' do
      result = gateway.wallet_snapshot

      expect(result).to eq(
        cash: 100_000,
        equity: 100_000,
        mtm: 0,
        exposure: 0
      )
    end

    it 'uses default balance when not configured' do
      allow(AlgoConfig).to receive(:fetch).and_return({ paper_trading: {} })

      result = gateway.wallet_snapshot

      expect(result[:cash]).to eq(100_000)
      expect(result[:equity]).to eq(100_000)
    end

    it 'handles AlgoConfig.fetch errors gracefully' do
      allow(AlgoConfig).to receive(:fetch).and_raise(StandardError.new('Config error'))

      result = gateway.wallet_snapshot

      expect(result).to eq(
        cash: 100_000,
        equity: 100_000,
        mtm: 0,
        exposure: 0
      )
    end

    it 'logs errors' do
      allow(AlgoConfig).to receive(:fetch).and_raise(StandardError.new('Config error'))

      expect(Rails.logger).to receive(:error).with(/GatewayPaper.*wallet_snapshot failed/)

      gateway.wallet_snapshot
    end
  end
end
