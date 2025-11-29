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
    allow(Orders::Placer).to receive(:exit_position!).and_return(double('order', id: '123'))
    allow(Orders::Placer).to receive(:buy_market!).and_return(double('order', id: '456'))
    allow(Orders::Placer).to receive(:sell_market!).and_return(double('order', id: '789'))
    allow(DhanHQ::Models::Position).to receive(:active).and_return([])
    allow(DhanHQ::Models::FundLimit).to receive(:fetch).and_return(
      double('funds', available: 100_000, utilized: 50_000, margin: 25_000)
    )
  end

  describe '#exit_market' do
    it 'generates unique client order ID with random component' do
      gateway.exit_market(tracker)

      expect(Orders::Placer).to have_received(:exit_position!) do |args|
        expect(args[:client_order_id]).to match(/^AS-EXIT-#{tracker.security_id}-\d+-[a-f0-9]{4}$/)
      end
    end

    it 'calls Placer.exit_position! with correct parameters' do
      gateway.exit_market(tracker)

      expect(Orders::Placer).to have_received(:exit_position!).with(
        seg: tracker.segment,
        sid: tracker.security_id,
        client_order_id: match(/^AS-EXIT-#{tracker.security_id}-\d+-[a-f0-9]{4}$/)
      )
    end

    it 'returns success hash when order is placed' do
      result = gateway.exit_market(tracker)

      expect(result).to eq({ success: true })
    end

    it 'returns failure hash when Placer returns nil' do
      allow(Orders::Placer).to receive(:exit_position!).and_return(nil)

      result = gateway.exit_market(tracker)

      expect(result).to eq({ success: false, error: 'exit failed' })
    end

    it 'generates different client order IDs for multiple calls' do
      coid1 = nil
      coid2 = nil

      allow(Orders::Placer).to receive(:exit_position!) do |args|
        coid1 ||= args[:client_order_id]
        coid2 = args[:client_order_id] if coid1
        double('order', id: '123')
      end

      gateway.exit_market(tracker)
      sleep 0.01 # Ensure different timestamp
      gateway.exit_market(tracker)

      expect(coid1).not_to eq(coid2)
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
          raise Timeout::Error.new('Timeout') if attempts < 2
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
          raise ArgumentError.new('Invalid argument')
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
          raise Timeout::Error.new('Timeout')
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
  end

  describe '#position' do
    let(:dhan_position) do
      double('position',
             security_id: '55111',
             exchange_segment: 'NSE_FNO',
             net_qty: 50,
             cost_price: 100.5,
             product_type: 'INTRADAY',
             position_type: 'LONG',
             trading_symbol: 'NIFTY24JAN20000CE')
    end

    it 'returns position hash when position exists' do
      allow(DhanHQ::Models::Position).to receive(:active).and_return([dhan_position])

      result = gateway.position(segment: 'NSE_FNO', security_id: '55111')

      expect(result).to eq(
        qty: 50,
        avg_price: BigDecimal('100.5'),
        product_type: 'INTRADAY',
        exchange_segment: 'NSE_FNO',
        position_type: 'LONG',
        trading_symbol: 'NIFTY24JAN20000CE'
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
                               cost_price: 200.0,
                               product_type: 'INTRADAY',
                               position_type: 'LONG',
                               trading_symbol: 'OTHER')
      allow(DhanHQ::Models::Position).to receive(:active).and_return([other_position, dhan_position])

      result = gateway.position(segment: 'NSE_FNO', security_id: '55111')

      expect(result[:qty]).to eq(50)
    end
  end

  describe '#wallet_snapshot' do
    it 'returns wallet hash with funds data' do
      result = gateway.wallet_snapshot

      expect(result).to eq(
        cash: 100_000,
        utilized: 50_000,
        margin: 25_000
      )
    end

    it 'handles errors gracefully and returns empty hash' do
      allow(DhanHQ::Models::FundLimit).to receive(:fetch).and_raise(StandardError.new('API error'))

      result = gateway.wallet_snapshot

      expect(result).to eq({})
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
