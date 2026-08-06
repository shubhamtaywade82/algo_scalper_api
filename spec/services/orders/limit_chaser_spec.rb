# frozen_string_literal: true

# rubocop:disable RSpec/VerifiedDoubles

require 'rails_helper'

RSpec.describe Orders::LimitChaser do
  let(:gateway) { double('GatewayLive') }
  let(:meta) { { product_type: 'INTRADAY', client_order_id: 'TEST_001' } }

  before do
    allow(AlgoConfig).to receive(:fetch).and_return(
      risk: {
        execution: {
          limit_chasing: {
            enabled: true,
            max_chase_seconds: 5,
            tick_interval_seconds: 1,
            fallback_to_market: true
          }
        }
      }
    )
    # Enable order placement by default
    allow(Orders::Placer).to receive(:order_placement_enabled?).and_return(true)
  end

  describe '.place_and_chase' do
    context 'when order placement is disabled (dry-run/paper)' do
      before do
        allow(Orders::Placer).to receive(:order_placement_enabled?).and_return(false)
        allow(gateway).to receive(:place_market_direct).and_return({ success: true, paper: true })
      end

      it 'bypasses chasing and places market direct' do
        result = described_class.place_and_chase(
          side: 'buy',
          segment: 'NSE_FNO',
          security_id: '55113',
          qty: 50,
          meta: meta,
          gateway: gateway
        )
        expect(result).to eq({ success: true, paper: true })
        expect(gateway).to have_received(:place_market_direct)
      end
    end

    context 'when live order placement is enabled' do
      let(:tick) { double('tick', bid: BigDecimal('98.0'), ask: BigDecimal('102.0')) }
      let(:order) { double('order', order_id: 'ORD_999') }

      before do
        allow(Live::TickQuery).to receive(:for_security).and_return(tick)
        allow(Orders::Placer).to receive(:buy_limit!).and_return(order)
      end

      it 'calculates midpoint and places limit order' do
        # Mock immediate fill
        allow(DhanHQ::Models::Order).to receive(:find).with('ORD_999').and_return(
          double('order_status', order_status: 'TRADED')
        )

        result = described_class.place_and_chase(
          side: 'buy',
          segment: 'NSE_FNO',
          security_id: '55113',
          qty: 50,
          meta: meta,
          gateway: gateway
        )

        expect(Orders::Placer).to have_received(:buy_limit!).with(
          seg: 'NSE_FNO',
          sid: '55113',
          qty: 50,
          price: 100.0, # (98 + 102) / 2
          client_order_id: 'TEST_001',
          product_type: 'INTRADAY'
        )
        expect(result.order_status).to eq('TRADED')
      end
    end
  end

  describe "Placer.buy_limit! real implementation (not stubbed)" do
    it "does not raise NameError when called with valid arguments" do
      allow(DhanHQ::Models::Order).to receive(:create!) do |_attributes|
        double("order", order_id: "ORD-1", id: "ORD-1")
      end
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("PLACE_ORDER").and_return("true")

      expect do
        Orders::Placer.buy_limit!(
          seg: "NSE_FNO",
          sid: "123456",
          qty: 50,
          price: 100.5,
          client_order_id: "LIMIT-TEST-1"
        )
      end.not_to raise_error
    end
  end
end

# rubocop:enable RSpec/VerifiedDoubles
