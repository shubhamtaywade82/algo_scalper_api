# frozen_string_literal: true

require "rails_helper"
require "bigdecimal"

RSpec.describe Orders::Placer do
  let(:order_double) { instance_double("DhanOrder") }
  let(:captured_attrs) { [] }
  let(:segment) { "NSE_FNO" }
  let(:security_id) { "123456" }
  let(:quantity) { 50 }

  before do
    allow(Rails.cache).to receive(:read).and_return(nil)
    allow(Rails.cache).to receive(:write)
    allow(DhanHQ::Models::Order).to receive(:create) do |attributes|
      captured_attrs << attributes
      order_double
    end
  end

  describe ".sell_market!" do
    it "normalizes long client order ids to meet the 30 character limit" do
      long_id = "AS-EXIT-12345678901234567890-9999999999"

      described_class.sell_market!(seg: segment, sid: security_id, qty: quantity, client_order_id: long_id)

      correlation_id = captured_attrs.last[:correlation_id]

      expect(correlation_id.length).to be <= 30
      expect(Rails.cache).to have_received(:write).with("coid:#{correlation_id}", true, expires_in: 20.minutes)
    end

    it "skips placing duplicate orders based on the normalized id" do
      long_id = "AS-EXIT-12345678901234567890-9999999999"
      allow(Rails.cache).to receive(:read).and_return(nil, true)

      described_class.sell_market!(seg: segment, sid: security_id, qty: quantity, client_order_id: long_id)
      described_class.sell_market!(seg: segment, sid: security_id, qty: quantity, client_order_id: long_id)

      expect(DhanHQ::Models::Order).to have_received(:create).once
    end
  end

  describe ".buy_market!" do
    it "uses the normalized id for correlation" do
      long_id = "AS-BUY-12345678901234567890-9999999999"

      described_class.buy_market!(seg: segment, sid: security_id, qty: quantity, client_order_id: long_id)

      expect(captured_attrs.last[:correlation_id].length).to be <= 30
    end

    it "places a market order even when risk parameters are provided" do
      stop_loss = BigDecimal("100.5")
      target = BigDecimal("125.25")

      described_class.buy_market!(
        seg: segment,
        sid: security_id,
        qty: quantity,
        client_order_id: "AS-BUY-ABC-#{Time.current.to_i}",
        stop_loss_price: stop_loss,
        target_price: target
      )

      expect(DhanHQ::Models::Order).to have_received(:create)
      expect(captured_attrs.last).to include(
        transaction_type: "BUY",
        order_type: "MARKET",
        product_type: "INTRADAY"
      )
      expect(captured_attrs.last).not_to have_key(:stop_loss_price)
      expect(captured_attrs.last).not_to have_key(:target_price)
    end
  end
end
