# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Orders::GatewayLive do
  let(:gateway) { described_class.new }
  let(:tracker) do
    create(:position_tracker, :option_position,
           status: 'active',
           segment: 'NSE_FNO',
           security_id: '55111',
           order_no: 'TEST123')
  end

  before do
    allow(Orders::Placer).to receive_messages(exit_position!: double('order', id: '123'),
                                              buy_market!: double('order', id: '456'), sell_market!: double('order', id: '789'))
    allow(DhanHQ::Models::Position).to receive(:active).and_return([])
    allow(DhanHQ::Models::Funds).to receive(:fetch).and_return(
      double('funds', available_balance: 100_000, utilized_amount: 50_000, margin: 25_000)
    )
  end

  describe '#cancel_order' do
    let(:order) { instance_double(DhanHQ::Models::Order, cancel!: true) }

    it 'finds and cancels the order' do
      allow(DhanHQ::Models::Order).to receive(:find).with('ORD-123').and_return(order)

      result = gateway.cancel_order('ORD-123')

      expect(result).to be(true)
      expect(DhanHQ::Models::Order).to have_received(:find).with('ORD-123')
      expect(order).to have_received(:cancel!)
    end

    it 'raises when the broker rejects the cancellation' do
      allow(DhanHQ::Models::Order).to receive(:find).with('ORD-123').and_return(order)
      allow(order).to receive(:cancel!).and_raise(DhanHQ::OrderError.new("Order#cancel failed"))

      expect { gateway.cancel_order('ORD-123') }.to raise_error(DhanHQ::OrderError)
    end
  end

  describe '#exit_market' do
    it 'uses provided client_order_id when passed' do
      gateway.exit_market(tracker, client_order_id: 'AS-EXIT-FIXED-001')

      expect(Orders::Placer).to have_received(:exit_position!).with(
        seg: tracker.segment,
        sid: tracker.security_id,
        client_order_id: 'AS-EXIT-FIXED-001'
      )
    end

    it 'falls back to tracker.exit_coid when no client_order_id is provided' do
      tracker.update!(exit_coid: 'AS-EXIT-FROM-TRACKER')

      gateway.exit_market(tracker)

      expect(Orders::Placer).to have_received(:exit_position!).with(
        seg: tracker.segment,
        sid: tracker.security_id,
        client_order_id: 'AS-EXIT-FROM-TRACKER'
      )
    end

    it 'derives the same deterministic id on every call (not a fresh random one) when ' \
       'neither client_order_id nor tracker.exit_coid is set' do
      # Regression: the old fallback (AS-EXIT-{sid}-{timestamp}-{random}) minted a new id
      # on every call, which defeats broker-side correlation-id dedup on a retried exit.
      coids = []
      allow(Orders::Placer).to receive(:exit_position!) do |**kwargs|
        coids << kwargs[:client_order_id]
        double('order', id: '123')
      end

      3.times { gateway.exit_market(tracker) }

      expect(coids).to all(match(/^AS-EXIT-[a-f0-9]{20}$/))
      expect(coids.uniq.size).to eq(1) # same id every time for the same tracker
    end

    it 'returns success hash with order id when order is placed' do
      result = gateway.exit_market(tracker, client_order_id: 'AS-EXIT-TEST-123')

      expect(result).to include(success: true, status: :accepted, order_id: nil, client_order_id: 'AS-EXIT-TEST-123')
    end

    it 'returns already_closed as success for duplicate/already-closed broker errors' do
      allow(Orders::Placer).to receive(:exit_position!).and_return(
        { error_code: 'POSITION_NOT_FOUND', message: 'Position already closed' }
      )

      result = gateway.exit_market(tracker, client_order_id: 'AS-EXIT-TEST-123')

      expect(result).to include(success: true, status: :already_closed, client_order_id: 'AS-EXIT-TEST-123')
    end

    it 'returns failure hash when Placer returns nil' do
      allow(Orders::Placer).to receive(:exit_position!).and_return(nil)

      result = gateway.exit_market(tracker)

      expect(result).to include(success: false, status: :failed, error: 'exit failed')
    end
  end

  describe '#flat_position' do
    it 'derives the same deterministic id (segment, security_id, day) on every call' do
      coids = []
      allow(Orders::Placer).to receive(:exit_position!) do |**kwargs|
        coids << kwargs[:client_order_id]
        double('order', id: '123')
      end

      3.times { gateway.flat_position(segment: 'NSE_FNO', security_id: '55111') }

      expect(coids).to all(match(/^AS-FLAT-[a-f0-9]{20}$/))
      expect(coids.uniq.size).to eq(1)
    end

    it 'derives a different id for a different security_id' do
      coids = []
      allow(Orders::Placer).to receive(:exit_position!) do |**kwargs|
        coids << kwargs[:client_order_id]
        double('order', id: '123')
      end

      gateway.flat_position(segment: 'NSE_FNO', security_id: '55111')
      gateway.flat_position(segment: 'NSE_FNO', security_id: '99999')

      expect(coids.uniq.size).to eq(2)
    end
  end

  describe '#place_market' do
    context 'with buy side' do
      it 'calls Placer.buy_market! with correct parameters' do
        gateway.place_market(
          side: 'buy',
          segment: 'NSE_FNO',
          security_id: '55111',
          qty: 50,
          meta: { price: 100.5, product_type: 'INTRADAY' }
        )

        expect(Orders::Placer).to have_received(:buy_market!).with(
          seg: 'NSE_FNO',
          sid: '55111',
          qty: 50,
          client_order_id: match(/^AS-buy-55111-\d+-[a-f0-9]{4}$/),
          price: 100.5,
          target_price: nil,
          stop_loss_price: nil,
          product_type: 'INTRADAY'
        )
      end

      it 'uses provided client_order_id from meta' do
        gateway.place_market(
          side: 'buy',
          segment: 'NSE_FNO',
          security_id: '55111',
          qty: 50,
          meta: { client_order_id: 'CUSTOM-123' }
        )

        expect(Orders::Placer).to have_received(:buy_market!).with(
          hash_including(client_order_id: 'CUSTOM-123')
        )
      end

      it 'passes bracket order parameters' do
        gateway.place_market(
          side: 'buy',
          segment: 'NSE_FNO',
          security_id: '55111',
          qty: 50,
          meta: {
            target_price: 120.0,
            stop_loss_price: 90.0
          }
        )

        expect(Orders::Placer).to have_received(:buy_market!).with(
          hash_including(
            target_price: 120.0,
            stop_loss_price: 90.0
          )
        )
      end
    end

    context 'with sell side' do
      it 'calls Placer.sell_market! with correct parameters' do
        gateway.place_market(
          side: 'sell',
          segment: 'NSE_FNO',
          security_id: '55111',
          qty: 50,
          meta: { product_type: 'INTRADAY' }
        )

        expect(Orders::Placer).to have_received(:sell_market!).with(
          seg: 'NSE_FNO',
          sid: '55111',
          qty: 50,
          client_order_id: match(/^AS-sell-55111-\d+-[a-f0-9]{4}$/),
          product_type: 'INTRADAY'
        )
      end
    end

    context 'with invalid side' do
      it 'raises error for invalid side' do
        expect do
          gateway.place_market(
            side: 'invalid',
            segment: 'NSE_FNO',
            security_id: '55111',
            qty: 50
          )
        end.to raise_error('invalid side')
      end
    end

    context 'with retry logic' do
      it 'retries on timeout errors' do
        attempts = 0
        allow(Orders::Placer).to receive(:buy_market!) do
          attempts += 1
          raise Timeout::Error, 'Timeout' if attempts < 2

          double('order', id: '123')
        end

        result = gateway.place_market(
          side: 'buy',
          segment: 'NSE_FNO',
          security_id: '55111',
          qty: 50
        )

        expect(result).to be_present
        expect(attempts).to eq(2)
      end

      it 'does not retry on non-retryable errors' do
        attempts = 0
        allow(Orders::Placer).to receive(:buy_market!) do
          attempts += 1
          raise ArgumentError, 'Invalid argument'
        end

        expect do
          gateway.place_market(
            side: 'buy',
            segment: 'NSE_FNO',
            security_id: '55111',
            qty: 50
          )
        end.to raise_error(ArgumentError)

        expect(attempts).to eq(1)
      end

      it 'retries up to RETRY_COUNT times' do
        attempts = 0
        allow(Orders::Placer).to receive(:buy_market!) do
          attempts += 1
          raise Timeout::Error, 'Timeout'
        end

        expect do
          gateway.place_market(
            side: 'buy',
            segment: 'NSE_FNO',
            security_id: '55111',
            qty: 50
          )
        end.to raise_error(Timeout::Error)

        expect(attempts).to eq(3) # RETRY_COUNT
      end
    end

    context 'when going end-to-end through the real Orders::Placer (regression: with_token_auto_heal used to swallow every error to nil, so this retry path never actually engaged)' do
      before do
        allow(Orders::Placer).to receive(:buy_market!).and_call_original
        allow(Rails.cache).to receive(:read).and_return(nil)
        allow(Rails.cache).to receive(:write).and_return(true)
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with('PLACE_ORDER').and_return('true')
        allow(Orders::Placer).to receive(:with_order_rate_limit).and_yield
      end

      it 'retries a broker timeout and succeeds on the second real attempt' do
        attempts = 0
        order_double = double('order', id: 'RETRY-OK')
        allow(DhanHQ::Models::Order).to receive(:create!) do
          attempts += 1
          raise Timeout::Error, 'Timeout' if attempts == 1

          order_double
        end

        result = gateway.place_market(side: 'buy', segment: 'NSE_FNO', security_id: '55111', qty: 50)

        expect(result).to eq(order_double)
        expect(attempts).to eq(2)
      end
    end
  end

  describe '#position' do
    let(:dhan_position) do
      double('position',
             security_id: '55111',
             exchange_segment: 'NSE_FNO',
             net_qty: 50,
             buy_avg: 100.5,
             product_type: 'INTRADAY',
             position_type: 'LONG',
             trading_symbol: 'NIFTY24JAN20000CE')
    end

    it 'returns position hash with unified shape when position exists' do
      allow(DhanHQ::Models::Position).to receive(:active).and_return([dhan_position])
      allow(Live::TickQuery).to receive(:for_security).and_return(double(ltp: BigDecimal('105.0')))

      result = gateway.position(segment: 'NSE_FNO', security_id: '55111')

      expect(result).to include(
        qty: 50,
        avg_price: BigDecimal('100.5'),
        upnl: BigDecimal('225.0'), # (105 - 100.5) * 50
        rpnl: BigDecimal(0),
        last_ltp: BigDecimal('105.0'),
        product_type: 'INTRADAY',
        exchange_segment: 'NSE_FNO',
        position_type: 'LONG',
        trading_symbol: 'NIFTY24JAN20000CE',
        status: 'active'
      )
    end

    it 'returns nil when position does not exist' do
      allow(DhanHQ::Models::Position).to receive(:active).and_return([])

      result = gateway.position(segment: 'NSE_FNO', security_id: '55111')

      expect(result).to be_nil
    end

    it 'handles fetch_positions errors gracefully' do
      allow(DhanHQ::Models::Position).to receive(:active).and_raise(StandardError.new('API error'))

      result = gateway.position(segment: 'NSE_FNO', security_id: '55111')

      expect(result).to be_nil
    end

    it 'matches position by security_id and segment' do
      other_position = double('position',
                              security_id: '55112',
                              exchange_segment: 'NSE_FNO',
                              net_qty: 100,
                              buy_avg: 200.0)
      allow(DhanHQ::Models::Position).to receive(:active).and_return([other_position, dhan_position])
      allow(Live::TickQuery).to receive(:for_security).and_return(double(ltp: BigDecimal('105.0')))

      result = gateway.position(segment: 'NSE_FNO', security_id: '55111')

      expect(result[:qty]).to eq(50)
    end
  end

  describe '#wallet_snapshot' do
    it 'returns wallet hash with unified shape' do
      result = gateway.wallet_snapshot

      expect(result).to eq(
        cash: 100_000,
        equity: 150_000,
        mtm: 0,
        exposure: 50_000,
        utilized: 50_000,
        margin: 25_000
      )
    end

    it 'handles errors gracefully and returns zeroed unified shape' do
      allow(DhanHQ::Models::Funds).to receive(:fetch).and_raise(StandardError.new('API error'))

      result = gateway.wallet_snapshot

      expect(result).to eq(cash: 0, equity: 0, mtm: 0, exposure: 0, utilized: 0, margin: 0)
    end
  end

  describe '#generate_client_order_id' do
    it 'generates unique IDs with random component' do
      id1 = gateway.send(:generate_client_order_id, 'buy', '55111')
      sleep 0.01
      id2 = gateway.send(:generate_client_order_id, 'buy', '55111')

      expect(id1).to match(/^AS-buy-55111-\d+-[a-f0-9]{4}$/)
      expect(id2).to match(/^AS-buy-55111-\d+-[a-f0-9]{4}$/)
      expect(id1).not_to eq(id2)
    end

    it 'includes prefix and security_id in ID' do
      id = gateway.send(:generate_client_order_id, 'sell', '55112')

      expect(id).to include('AS-sell-55112')
    end
  end
end
