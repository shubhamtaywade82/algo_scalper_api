# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Orders::Commands::CancelOrderCommand do
  subject(:command) do
    described_class.new(
      gateway: gateway,
      tracker: tracker,
      order_id: 'DHAN456'
    )
  end

  let(:gateway) { instance_double(Orders::GatewayPaper) }
  let(:tracker) { build_stubbed(:position_tracker, status: 'pending', order_no: 'ORD004') }

  # ── Successful cancel ───────────────────────────────────────────────────────

  describe '#call — success path' do
    before do
      allow(gateway).to receive(:cancel_order).with('DHAN456').and_return({ success: true })
    end

    it 'returns a successful result' do
      result = command.call
      expect(result).to be_success
      expect(result.payload[:order_id]).to eq('DHAN456')
    end
  end

  # ── Broker rejection ────────────────────────────────────────────────────────

  describe '#call — broker rejects' do
    before do
      allow(gateway).to receive(:cancel_order).and_return({ success: false, message: 'order not found' })
    end

    it 'returns failure with cancel_rejected' do
      result = command.call
      expect(result).to be_failure
      expect(result.reason).to eq('cancel_rejected')
    end
  end

  # ── Validation ──────────────────────────────────────────────────────────────

  context 'when order_id is blank' do
    subject(:command) do
      described_class.new(gateway: gateway, tracker: tracker, order_id: '')
    end

    it 'fails with missing_order_id' do
      result = command.call
      expect(result).to be_failure
      expect(result.reason).to eq('missing_order_id')
    end
  end
end
