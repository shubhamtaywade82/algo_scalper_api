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

      expect(result).to eq({ success: true, exit_price: BigDecimal('101.5') })
    end

    it 'uses entry_price as fallback when LTP is nil' do
      allow(Live::TickCache).to receive(:ltp).and_return(nil)

      result = gateway.exit_market(tracker)

      expect(result).to eq({ success: true, exit_price: BigDecimal('100.0') })
    end

    it 'uses entry_price as fallback when LTP raises error' do
      allow(Live::TickCache).to receive(:ltp).and_raise(StandardError.new('Cache error'))

      result = gateway.exit_market(tracker)

      expect(result).to eq({ success: true, exit_price: BigDecimal('100.0') })
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
    context 'when tracker does not exist' do
      it 'creates new PositionTracker' do
        result = gateway.place_market(
          side: 'buy',
          segment: 'NSE_FNO',
          security_id: '55111',
          qty: 50,
          meta: { price: 100.5, symbol: 'NIFTY24JAN20000CE' }
        )

        expect(result[:success]).to be true
        expect(result[:paper]).to be true
        expect(result[:tracker_id]).to be_present

        tracker = PositionTracker.find(result[:tracker_id])
        expect(tracker.status).to eq('active')
        expect(tracker.quantity).to eq(50)
        expect(tracker.avg_price).to eq(100.5)
        expect(tracker.symbol).to eq('NIFTY24JAN20000CE')
      end

      it 'generates unique order_no' do
        result1 = gateway.place_market(
          side: 'buy',
          segment: 'NSE_FNO',
          security_id: '55111',
          qty: 50
        )
        result2 = gateway.place_market(
          side: 'buy',
          segment: 'NSE_FNO',
          security_id: '55112',
          qty: 50
        )

        tracker1 = PositionTracker.find(result1[:tracker_id])
        tracker2 = PositionTracker.find(result2[:tracker_id])

        expect(tracker1.order_no).not_to eq(tracker2.order_no)
        expect(tracker1.order_no).to start_with('PAPER-')
        expect(tracker2.order_no).to start_with('PAPER-')
      end

      it 'uses security_id as symbol fallback' do
        result = gateway.place_market(
          side: 'buy',
          segment: 'NSE_FNO',
          security_id: '55111',
          qty: 50
        )

        tracker = PositionTracker.find(result[:tracker_id])
        expect(tracker.symbol).to eq('55111')
      end

      it 'sets side to uppercase' do
        result = gateway.place_market(
          side: 'buy',
          segment: 'NSE_FNO',
          security_id: '55111',
          qty: 50
        )

        tracker = PositionTracker.find(result[:tracker_id])
        expect(tracker.side).to eq('BUY')
      end

      it 'uses 0 as avg_price fallback' do
        result = gateway.place_market(
          side: 'buy',
          segment: 'NSE_FNO',
          security_id: '55111',
          qty: 50
        )

        tracker = PositionTracker.find(result[:tracker_id])
        expect(tracker.avg_price).to eq(0)
      end
    end

    context 'when tracker already exists' do
      it 'returns existing tracker' do
        existing_tracker = create(:position_tracker,
                                  status: 'active',
                                  segment: 'NSE_FNO',
                                  security_id: '55111')

        result = gateway.place_market(
          side: 'buy',
          segment: 'NSE_FNO',
          security_id: '55111',
          qty: 50
        )

        expect(result[:tracker_id]).to eq(existing_tracker.id)
        expect(PositionTracker.where(segment: 'NSE_FNO', security_id: '55111').count).to eq(1)
      end
    end

    context 'with errors' do
      it 'handles PositionTracker.create! failures gracefully' do
        allow(PositionTracker).to receive(:active_for).and_return(nil)
        allow(PositionTracker).to receive(:create!).and_raise(ActiveRecord::RecordInvalid.new(PositionTracker.new))

        result = gateway.place_market(
          side: 'buy',
          segment: 'NSE_FNO',
          security_id: '55111',
          qty: 50
        )

        expect(result[:success]).to be false
        expect(result[:error]).to be_present
        expect(result[:paper]).to be true
      end

      it 'logs errors' do
        allow(PositionTracker).to receive(:active_for).and_return(nil)
        allow(PositionTracker).to receive(:create!).and_raise(StandardError.new('DB error'))

        expect(Rails.logger).to receive(:error).with(/GatewayPaper.*place_market failed/)

        gateway.place_market(
          side: 'buy',
          segment: 'NSE_FNO',
          security_id: '55111',
          qty: 50
        )
      end
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
