# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Orders::MultiLegExecutor do
  let(:legs) do
    [
      {
        leg_order: 2,
        type: :short_put,
        action: 'sell',
        security_id: '12345',
        segment: 'NSE_FNO',
        strike: 24_000,
        quantity: 50
      },
      {
        leg_order: 1,
        type: :long_put,
        action: 'buy',
        security_id: '12344',
        segment: 'NSE_FNO',
        strike: 23_900,
        quantity: 50
      }
    ]
  end

  describe '#call' do
    context 'when in paper mode' do
      it 'executes legs in hedge-first order (buy first, then sell)' do
        result = described_class.execute(legs: legs, mode: :paper)

        expect(result[:success]).to be(true)
        expect(result[:legs].size).to eq(2)
        expect(result[:legs].first.dig(:leg, :type)).to eq(:long_put)
        expect(result[:legs].second.dig(:leg, :type)).to eq(:short_put)
      end

      it 'handles blank legs gracefully' do
        result = described_class.execute(legs: [], mode: :paper)
        expect(result[:success]).to be(false)
        expect(result[:error]).to include('no legs')
      end
    end

    context 'when in live mode (regression: wait_for_fill called a private, wrong-shaped method)' do
      let(:single_leg) { [legs.last] } # just the buy hedge leg
      # DhanHQ::Models::Order defines attribute readers dynamically (not via def), so
      # instance_double can't verify them — plain doubles, matching gateway_live_spec.rb's
      # existing convention for stand-in Order objects.
      let(:placed_order) { double('order', order_id: 'ORD-777') } # rubocop:disable RSpec/VerifiedDoubles
      let(:traded_status) do
        double('order', order_status: 'TRADED', average_traded_price: 15.25, # rubocop:disable RSpec/VerifiedDoubles
                        filled_qty: 50, order_id: 'ORD-777')
      end

      before do
        allow(Orders::Placer).to receive(:buy_market!).and_return(placed_order)
        # wait_for_fill's poll loop runs on the executor instance, created internally by
        # .execute — any_instance_of is the only way to stub its sleep before that instance exists.
        allow_any_instance_of(described_class).to receive(:sleep) # rubocop:disable RSpec/AnyInstance
      end

      it 'polls order status via the public DhanHQ::Models::Order API and fills successfully' do
        allow(DhanHQ::Models::Order).to receive(:find).with('ORD-777').and_return(traded_status)

        result = described_class.execute(legs: single_leg, mode: :live)

        expect(result[:success]).to be(true)
        expect(result[:legs].first.dig(:result, :fill_price)).to eq(15.25)
        expect(result[:legs].first.dig(:result, :fill_quantity)).to eq(50)
      end

      it 'falls back to find_by_correlation when the placed order has no order_id' do
        allow(Orders::Placer).to receive(:buy_market!).and_return({}) # e.g. a bare Hash response
        allow(DhanHQ::Models::Order).to receive(:find_by_correlation).with('ML_TEST_L1').and_return(traded_status)

        result = described_class.execute(legs: single_leg, group_id: 'ML_TEST', mode: :live)

        expect(result[:success]).to be(true)
        expect(DhanHQ::Models::Order).to have_received(:find_by_correlation).with('ML_TEST_L1')
      end

      it 'treats a rejected order as a failed fill and rolls back' do
        allow(DhanHQ::Models::Order).to receive(:find).with('ORD-777').and_return(
          double('order', order_status: 'REJECTED') # rubocop:disable RSpec/VerifiedDoubles
        )

        result = described_class.execute(legs: single_leg, mode: :live)

        expect(result[:success]).to be(false)
        expect(result[:error]).to include('fill failed')
      end

      it 'does not crash when the order lookup itself errors' do
        allow(DhanHQ::Models::Order).to receive(:find).and_raise(DhanHQ::OrderError, 'lookup failed')

        expect { described_class.execute(legs: single_leg, mode: :live) }.not_to raise_error
      end
    end

    context 'when a leg placement fails' do
      it 'triggers rollback for previously filled legs' do
        gateway = instance_double(Orders::GatewayPaper)
        allow(Orders::GatewayFactory).to receive(:selected_gateway).and_return(gateway)

        # First leg succeeds (buy hedge 12344)
        allow(gateway).to receive(:place_market).with(hash_including(security_id: '12344', side: 'BUY')).and_return({ success: true, fill_price: 15.0 })
        # Second leg fails (sell short 12345)
        allow(gateway).to receive(:place_market).with(hash_including(security_id: '12345', side: 'SELL')).and_return({ success: false, error: 'Margin error' })
        # Rollback execution for first leg (sell 12344 to close)
        allow(gateway).to receive(:place_market).with(hash_including(security_id: '12344', side: 'SELL')).and_return({ success: true })

        result = described_class.execute(legs: legs, mode: :paper)
        expect(result[:success]).to be(false)
        expect(result[:rolled_back]).to be(true)
      end
    end
  end
end
