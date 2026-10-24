# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Orders::Commands::ExitOrderCommand do
  subject(:command) do
    described_class.new(
      gateway: gateway,
      tracker: tracker,
      client_order_id: 'COID-XYZ',
      reason: 'stop_loss'
    )
  end

  let(:gateway) { instance_double(Orders::GatewayPaper) }
  let(:tracker) { build_stubbed(:position_tracker, status: 'active', order_no: 'ORD002') }

  # ── Successful exit ─────────────────────────────────────────────────────────

  describe '#call — success path' do
    before do
      allow(gateway).to receive(:exit_market)
        .and_return({ success: true, exit_price: BigDecimal('245.50'), paper: true })
    end

    it 'returns a successful result' do
      result = command.call
      expect(result).to be_success
      expect(result.payload[:exit_price]).to eq(BigDecimal('245.50'))
      expect(result.payload[:reason]).to eq('stop_loss')
    end
  end

  # ── Paper gateway (paper: true with explicit success) ───────────────────────

  describe '#call — paper gateway response' do
    before do
      allow(gateway).to receive(:exit_market)
        .and_return({ success: true, paper: true, exit_price: 200.0 })
    end

    it 'treats a successful paper response as success' do
      result = command.call
      expect(result).to be_success
    end
  end

  # ── Paper gateway response missing success key (regression: must not
  # masquerade as success just because paper: true is present) ───────────────

  describe '#call — paper gateway response missing success key entirely' do
    before do
      allow(gateway).to receive(:exit_market)
        .and_return({ paper: true, exit_price: 200.0 })
    end

    it 'does not treat an ambiguous response as success' do
      result = command.call
      expect(result).to be_failure
      expect(result.reason).to eq('broker_rejected')
    end
  end

  # ── Validation failures ─────────────────────────────────────────────────────

  context 'when tracker is not active' do
    let(:tracker) { build_stubbed(:position_tracker, status: 'exited', order_no: 'ORD003') }

    it 'fails with not_active' do
      result = command.call
      expect(result).to be_failure
      expect(result.reason).to eq('not_active')
    end
  end

  context 'when client_order_id is blank' do
    subject(:command) do
      described_class.new(
        gateway: gateway,
        tracker: tracker,
        client_order_id: ''
      )
    end

    it 'fails with missing_client_order_id' do
      result = command.call
      expect(result).to be_failure
      expect(result.reason).to eq('missing_client_order_id')
    end
  end

  # ── Broker rejection ────────────────────────────────────────────────────────

  describe '#call — broker rejects' do
    before do
      allow(gateway).to receive(:exit_market).and_return({ success: false })
    end

    it 'returns failure with broker_rejected' do
      result = command.call
      expect(result).to be_failure
      expect(result.reason).to eq('broker_rejected')
    end
  end
end
