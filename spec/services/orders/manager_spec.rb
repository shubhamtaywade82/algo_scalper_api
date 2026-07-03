# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Orders::Manager do
  describe '.place_market_buy' do
    let(:segment) { 'NSE_FNO' }
    let(:security_id) { '12345' }
    let(:qty) { 75 }
    let(:reason) { 'test_signal' }
    let(:metadata) { { source: 'test' } }

    before do
      allow(Orders::Placer).to receive(:buy_market!)
    end

    it 'delegates to Orders::Placer.buy_market! with correct args' do
      described_class.place_market_buy(segment: segment, security_id: security_id, qty: qty, reason: reason)

      expect(Orders::Placer).to have_received(:buy_market!) do |args|
        aggregate_failures do
          expect(args[:seg]).to eq(segment)
          expect(args[:sid]).to eq(security_id)
          expect(args[:qty]).to eq(qty)
          expect(args[:client_order_id]).to match(/^NSE_FNO-12345-test_signal-\d{6}$/)
        end
      end
    end

    it 'passes metadata to the log message' do
      allow(Rails.logger).to receive(:info)

      described_class.place_market_buy(segment: segment, security_id: security_id, qty: qty, reason: reason, metadata: metadata)

      expect(Rails.logger).to have_received(:info).with(/metadata.*#{metadata.inspect}/)
    end

    context 'when segment is blank' do
      it 'returns nil without placing an order' do
        result = described_class.place_market_buy(segment: '', security_id: security_id, qty: qty, reason: reason)

        expect(result).to be_nil
        expect(Orders::Placer).not_to have_received(:buy_market!)
      end
    end

    context 'when security_id is blank' do
      it 'returns nil without placing an order' do
        result = described_class.place_market_buy(segment: segment, security_id: nil, qty: qty, reason: reason)

        expect(result).to be_nil
        expect(Orders::Placer).not_to have_received(:buy_market!)
      end
    end

    context 'with various reason strings' do
      it 'parameterizes the reason for the client_order_id' do
        described_class.place_market_buy(segment: segment, security_id: security_id, qty: qty, reason: 'My Signal!')

        expect(Orders::Placer).to have_received(:buy_market!) do |args|
          expect(args[:client_order_id]).to match(/^NSE_FNO-12345-my-signal-\d{6}$/)
        end
      end

      it 'falls back to "signal" for blank reason' do
        described_class.place_market_buy(segment: segment, security_id: security_id, qty: qty, reason: '')

        expect(Orders::Placer).to have_received(:buy_market!) do |args|
          expect(args[:client_order_id]).to match(/^NSE_FNO-12345-signal-\d{6}$/)
        end
      end
    end
  end
end
