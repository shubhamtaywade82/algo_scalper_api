# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Orders::Executor do
  let(:gateway) { instance_double(Orders::Gateway) }

  before do
    config = instance_double(Orders::Config, gateway: gateway)
    allow(Orders).to receive(:config).and_return(config)
    allow(Rails.logger).to receive(:info)
    allow(Rails.logger).to receive(:error)
  end

  describe '.place_buy' do
    it 'delegates to the gateway place_market with buy side' do
      allow(gateway).to receive(:place_market).and_return({ success: true })

      described_class.place_buy(symbol: 'NIFTY', qty: 65, segment: 'NSE_FNO', security_id: '12345', ltp: 150.0)

      expect(gateway).to have_received(:place_market).with(
        side: 'buy',
        segment: 'NSE_FNO',
        security_id: '12345',
        qty: 65,
        meta: { symbol: 'NIFTY', ltp: 150.0 }
      )
    end

    it 'works without ltp' do
      allow(gateway).to receive(:place_market).and_return({ success: true })

      described_class.place_buy(symbol: 'NIFTY', qty: 65, segment: 'NSE_FNO', security_id: '12345')

      expect(gateway).to have_received(:place_market).with(
        hash_including(meta: { symbol: 'NIFTY', ltp: nil })
      )
    end

    it 'returns the gateway result' do
      allow(gateway).to receive(:place_market).and_return({ success: true, order_id: 'ORD123' })

      result = described_class.place_buy(symbol: 'NIFTY', qty: 65, segment: 'NSE_FNO', security_id: '12345')

      expect(result).to eq({ success: true, order_id: 'ORD123' })
    end
  end

  describe '.update_sl' do
    let(:tracker) { instance_double(PositionTracker, active?: true, order_no: 'ORD123', id: 1) }

    before do
      allow(Orders::BracketPlacer).to receive(:update_bracket).and_return({ success: true, sl_price: 105.0 })
    end

    it 'updates the stop loss via BracketPlacer' do
      result = described_class.update_sl(tracker: tracker, sl_price: 105.0, reason: 'trailing_stop')

      expect(Orders::BracketPlacer).to have_received(:update_bracket).with(
        tracker: tracker,
        sl_price: 105.0,
        reason: 'trailing_stop'
      )
      expect(result).to be true
    end

    it 'returns false when tracker is nil' do
      result = described_class.update_sl(tracker: nil, sl_price: 105.0, reason: 'test')

      expect(result).to be false
      expect(Orders::BracketPlacer).not_to have_received(:update_bracket)
    end

    it 'returns false when tracker is not active' do
      inactive_tracker = instance_double(PositionTracker, active?: false)
      result = described_class.update_sl(tracker: inactive_tracker, sl_price: 105.0, reason: 'test')

      expect(result).to be false
      expect(Orders::BracketPlacer).not_to have_received(:update_bracket)
    end

    it 'returns false when sl_price is nil' do
      result = described_class.update_sl(tracker: tracker, sl_price: nil, reason: 'test')

      expect(result).to be false
      expect(Orders::BracketPlacer).not_to have_received(:update_bracket)
    end

    it 'returns false when sl_price is zero or negative' do
      result = described_class.update_sl(tracker: tracker, sl_price: 0, reason: 'test')

      expect(result).to be false
      expect(Orders::BracketPlacer).not_to have_received(:update_bracket)
    end

    it 'returns false when BracketPlacer returns failure' do
      allow(Orders::BracketPlacer).to receive(:update_bracket).and_return({ success: false, error: 'Tracker not found' })

      result = described_class.update_sl(tracker: tracker, sl_price: 105.0, reason: 'test')

      expect(result).to be false
    end

    it 'logs and returns false on exception' do
      allow(Orders::BracketPlacer).to receive(:update_bracket).and_raise(StandardError, 'unexpected error')

      result = described_class.update_sl(tracker: tracker, sl_price: 105.0, reason: 'test')

      expect(result).to be false
      expect(Rails.logger).to have_received(:error).with(/Failed to update SL/)
    end

    it 'rounds sl_price to 2 decimal places' do
      described_class.update_sl(tracker: tracker, sl_price: 105.6789, reason: 'test')

      expect(Orders::BracketPlacer).to have_received(:update_bracket).with(
        tracker: tracker,
        sl_price: 105.68,
        reason: 'test'
      )
    end
  end
end
