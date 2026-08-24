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
