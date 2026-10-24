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
    let(:tick) do
      instance_double(MarketTick, ltp: 101.5, bid: 101.0, ask: 102.0)
    end

    before do
      allow(Live::TickQuery).to receive(:for_security).and_return(tick)
      allow(AlgoConfig).to receive(:dig).and_call_original
      allow(AlgoConfig).to receive(:dig).with('paper_trading', 'slippage', 'enabled').and_return(false)
    end

    it 'returns success hash with exit_price from bid for LONG position' do
      tracker.update!(position_side: 'LONG')
      result = gateway.exit_market(tracker)

      expect(result).to include(
        success: true,
        exit_price: BigDecimal('101.0'),
        order_id: "PAPER-EXIT-#{tracker.id}",
        client_order_id: "PAPER-EXIT-#{tracker.id}",
        status: :accepted,
        paper: true
      )
    end

    it 'returns success hash with exit_price from ask for SHORT position' do
      tracker.update!(position_side: 'SHORT')
      result = gateway.exit_market(tracker)

      expect(result).to include(
        success: true,
        exit_price: BigDecimal('102.0')
      )
    end

    it 'uses entry_price as fallback when tick is nil' do
      allow(Live::TickQuery).to receive(:for_security).and_return(nil)

      result = gateway.exit_market(tracker)

      expect(result).to include(success: true, exit_price: BigDecimal('100.0'))
    end

    it 'falls back to ltp when bid/ask are missing' do
      allow(tick).to receive_messages(bid: nil, ask: nil)
      tracker.update!(position_side: 'LONG')

      result = gateway.exit_market(tracker)

      expect(result).to include(success: true, exit_price: BigDecimal('101.5'))
    end

    it 'uses provided client_order_id as order identity' do
      result = gateway.exit_market(tracker, client_order_id: 'COID-123')

      expect(result).to include(order_id: 'COID-123', client_order_id: 'COID-123', status: :accepted)
    end

    it 'does not update tracker directly' do
      allow(tracker).to receive(:mark_exited!)

      gateway.exit_market(tracker)

      tracker.reload
      expect(tracker).not_to have_received(:mark_exited!)
      expect(tracker.status).to eq('active')
    end

    it 'returns BigDecimal for exit_price' do
      result = gateway.exit_market(tracker)

      expect(result[:exit_price]).to be_a(BigDecimal)
    end

    it 'ignores a stale cached tick and uses the REST API price instead' do
      stale_tick = MarketTick.new(segment: 'NSE_FNO', security_id: '55111', ltp: 999.0, timestamp: 1.hour.ago,
                                  oi: nil, oi_change: nil, bid: 999.0, ask: 999.0, volume: nil, prev_close: nil)
      allow(Live::TickQuery).to receive(:for_security).and_return(stale_tick)
      allow(DhanHQ::Models::MarketFeed).to receive(:ltp).and_return(
        { 'status' => 'success', 'data' => { 'NSE_FNO' => { '55111' => { 'last_price' => 105.0 } } } }
      )
      tracker.update!(position_side: 'LONG')

      result = gateway.exit_market(tracker)

      expect(result[:exit_price]).to eq(BigDecimal('105.0'))
    end
  end

  describe '#place_market' do
    let(:tick) do
      instance_double(MarketTick, ltp: 101.5, bid: 101.0, ask: 102.0)
    end

    before do
      allow(Live::TickQuery).to receive(:for_security).and_return(tick)
      allow(AlgoConfig).to receive(:dig).and_call_original
      allow(AlgoConfig).to receive(:dig).with('paper_trading', 'slippage', 'enabled').and_return(true)
      allow(AlgoConfig).to receive(:dig).with('paper_trading', 'slippage', 'market_buy_ticks').and_return(2)
      allow(AlgoConfig).to receive(:dig).with('paper_trading', 'slippage', 'market_sell_ticks').and_return(3)
    end

    it 'uses ask + slippage for BUY side' do
      result = gateway.place_market(
        side: 'buy',
        segment: 'NSE_FNO',
        security_id: '55111',
        qty: 50
      )

      # ask (102.0) + (2 * 0.05) = 102.1
      expect(result).to include(success: true, paper: true, fill_price: 102.1)
    end

    it 'uses bid - slippage for SELL side' do
      result = gateway.place_market(
        side: 'sell',
        segment: 'NSE_FNO',
        security_id: '55111',
        qty: 50
      )

      # bid (101.0) - (3 * 0.05) = 100.85
      expect(result).to include(success: true, paper: true, fill_price: 100.85)
    end

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
    it 'delegates to Ledger::WalletReader for the paper snapshot' do
      ledger_snapshot = {
        cash: 119_820.0, equity: 119_820.0, mtm: 0.0, exposure: 0.0,
        utilized: 0.0, margin: 0, realized_pnl: 25_460.0, brokerage_expense: 5_640.0, source: 'ledger'
      }
      allow(Ledger::WalletReader).to receive(:snapshot).with(mode: :paper).and_return(ledger_snapshot)

      result = gateway.wallet_snapshot

      expect(result).to eq(
        cash: 119_820.0, equity: 119_820.0, mtm: 0.0,
        exposure: 0.0, utilized: 0.0, margin: 0
      )
    end

    it 'falls back to the default shape when the ledger errors' do
      allow(Ledger::WalletReader).to receive(:snapshot).and_raise(StandardError.new('Ledger error'))

      result = gateway.wallet_snapshot

      expect(result).to eq(
        cash: 100_000, equity: 100_000, mtm: 0, exposure: 0, utilized: 0, margin: 0
      )
    end

    it 'logs ledger errors' do
      allow(Ledger::WalletReader).to receive(:snapshot).and_raise(StandardError.new('Ledger error'))
      allow(Rails.logger).to receive(:error).with(/GatewayPaper.*wallet_snapshot failed/)

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
