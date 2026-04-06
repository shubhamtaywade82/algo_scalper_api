# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Orders::GatewayPaper do
  let(:gateway) { described_class.new }
  let(:tracker) do
    create(:position_tracker, :option_position,
           status: 'active',
           paper: true,
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
      allow(tracker).to receive(:mark_exited!)

      gateway.exit_market(tracker)

      expect(tracker).not_to have_received(:mark_exited!)
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
      allow(Rails.logger).to receive(:error)

      result = gateway.place_market(
        side: 'buy',
        segment: 'NSE_FNO',
        security_id: '55111',
        qty: 50
      )

      expect(Rails.logger).to have_received(:error).with(/GatewayPaper.*place_market failed/)
      expect(result).to include(success: false, paper: true)
      expect(result[:error]).to be_present
    end
  end

  describe '#position' do
    context 'when tracker exists' do
      it 'returns position hash with unified shape' do
        tracker.update!(quantity: 50, avg_price: 100.5, side: 'BUY', symbol: 'NIFTY24JAN20000CE')
        allow(Live::TickQuery).to receive(:for_security).and_return(double(ltp: BigDecimal('102.0')))

        result = gateway.position(segment: 'NSE_FNO', security_id: '55111')

        expect(result).to include(
          qty: 50,
          avg_price: 100.5,
          upnl: be_a(BigDecimal),
          rpnl: BigDecimal(0),
          last_ltp: BigDecimal('102.0'),
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
    it 'returns unified wallet keys with configured balance when no positions' do
      result = gateway.wallet_snapshot

      expect(result).to eq(
        cash: 100_000,
        equity: 100_000,
        mtm: 0,
        exposure: 0,
        utilized: 0,
        margin: 0
      )
    end

    it 'adds cumulative realized PnL from paper exits on prior days' do
      create(:position_tracker, :option_position, :exited, paper: true,
                                                           segment: 'NSE_FNO',
                                                           order_no: 'PAPER-EXIT-PRIOR',
                                                           exited_at: 2.days.ago,
                                                           last_pnl_rupees: 5_000)

      result = gateway.wallet_snapshot

      expect(result).to eq(
        cash: 105_000,
        equity: 105_000,
        mtm: 0,
        exposure: 0,
        utilized: 0,
        margin: 0
      )
    end

    it 'reduces cash and sets exposure to deployed premium for active paper legs' do
      create(:position_tracker, :option_position, paper: true,
                                                  segment: 'NSE_FNO',
                                                  order_no: 'PAPER-ACTIVE-1',
                                                  status: 'active',
                                                  entry_price: 100.0,
                                                  quantity: 50,
                                                  last_pnl_rupees: 200)

      result = gateway.wallet_snapshot

      expect(result).to eq(
        cash: 95_000,
        equity: 100_200,
        mtm: 200,
        exposure: 5_000,
        utilized: 5_000,
        margin: 0
      )
    end

    context 'when realized_scope is daily' do
      before do
        allow(AlgoConfig).to receive(:fetch).and_return(
          { paper_trading: { balance: 100_000, realized_scope: 'daily' } }
        )
      end

      it 'ignores exits before today for realized cash' do
        create(:position_tracker, :option_position, :exited, paper: true,
                                                             segment: 'NSE_FNO',
                                                             order_no: 'PAPER-EXIT-YEST',
                                                             exited_at: 1.day.ago,
                                                             last_pnl_rupees: 7_000)

        result = gateway.wallet_snapshot

        expect(result).to eq(
          cash: 100_000,
          equity: 100_000,
          mtm: 0,
          exposure: 0,
          utilized: 0,
          margin: 0
        )
      end

      it 'includes exits that exited today' do
        create(:position_tracker, :option_position, :exited, paper: true,
                                                             segment: 'NSE_FNO',
                                                             order_no: 'PAPER-EXIT-TODAY',
                                                             exited_at: Time.zone.now,
                                                             last_pnl_rupees: 3_000)

        result = gateway.wallet_snapshot

        expect(result).to eq(
          cash: 103_000,
          equity: 103_000,
          mtm: 0,
          exposure: 0,
          utilized: 0,
          margin: 0
        )
      end
    end

    it 'clamps cash at zero when base plus realized is below deployed' do
      create(:position_tracker, :option_position, paper: true,
                                                  segment: 'NSE_FNO',
                                                  order_no: 'PAPER-BIG-DEPLOY',
                                                  status: 'active',
                                                  entry_price: 10_000.0,
                                                  quantity: 20,
                                                  last_pnl_rupees: 0)

      allow(AlgoConfig).to receive(:fetch).and_return({ paper_trading: { balance: 50_000 } })

      result = gateway.wallet_snapshot

      expect(result).to eq(
        cash: 0,
        equity: 200_000,
        mtm: 0,
        exposure: 200_000,
        utilized: 200_000,
        margin: 0
      )
    end

    it 'uses default balance when not configured' do
      allow(AlgoConfig).to receive(:fetch).and_return({ paper_trading: {} })

      result = gateway.wallet_snapshot

      expect(result).to eq(
        cash: 100_000,
        equity: 100_000,
        mtm: 0,
        exposure: 0,
        utilized: 0,
        margin: 0
      )
    end

    it 'handles AlgoConfig.fetch errors gracefully' do
      allow(AlgoConfig).to receive(:fetch).and_raise(StandardError.new('Config error'))

      result = gateway.wallet_snapshot

      expect(result).to eq(
        cash: 100_000,
        equity: 100_000,
        mtm: 0,
        exposure: 0,
        utilized: 0,
        margin: 0
      )
    end

    it 'logs errors' do
      allow(Rails.logger).to receive(:error)
      allow(AlgoConfig).to receive(:fetch).and_raise(StandardError.new('Config error'))

      gateway.wallet_snapshot

      expect(Rails.logger).to have_received(:error).with(/GatewayPaper.*wallet_snapshot failed/)
    end
  end

  describe '#cancel_order' do
    it 'returns a simulated cancel acknowledgement' do
      result = gateway.cancel_order('PAPER-ORD-1')

      expect(result).to eq(
        success: true,
        order_id: 'PAPER-ORD-1',
        status: :canceled,
        paper: true
      )
    end
  end
end
