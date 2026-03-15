# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Orders::Commands::PlaceOrderCommand do
  let(:gateway) { instance_double('Orders::GatewayPaper') }

  # tracker is intentionally absent — it doesn't exist at placement time
  let(:default_params) do
    {
      gateway:     gateway,
      side:        :buy,
      segment:     'NSE_FNO',
      security_id: '12345',
      qty:         50,
      meta:        { index_key: 'NIFTY' }
    }
  end

  subject(:command) { described_class.new(**default_params) }

  # ── Successful execution ────────────────────────────────────────────────────

  describe '#call — success path' do
    before do
      allow(gateway).to receive(:place_market).and_return(
        { success: true, order_id: 'DHAN123', paper: true }
      )
    end

    it 'returns a successful CommandResult' do
      result = command.call
      expect(result).to be_success
      expect(result.payload[:order_id]).to eq('DHAN123')
      expect(result.payload[:paper]).to be true
    end

    it 'passes keyword args to gateway' do
      expect(gateway).to receive(:place_market).with(
        side: 'BUY', segment: 'NSE_FNO', security_id: '12345', qty: 50, meta: { index_key: 'NIFTY' }
      ).and_return({ success: true, order_id: 'X' })
      command.call
    end
  end

  # ── Broker rejection ────────────────────────────────────────────────────────

  describe '#call — broker rejects' do
    before do
      allow(gateway).to receive(:place_market).and_return({ success: false, error: 'limit exceeded' })
    end

    it 'returns failure with reason broker_rejected' do
      result = command.call
      expect(result).to be_failure
      expect(result.reason).to eq('broker_rejected')
    end
  end

  # ── Validation failures ─────────────────────────────────────────────────────

  context 'when gateway is nil' do
    subject(:command) { described_class.new(**default_params.merge(gateway: nil)) }

    it 'fails with missing_gateway' do
      result = command.call
      expect(result).to be_failure
      expect(result.reason).to eq('missing_gateway')
    end
  end

  context 'when qty is zero' do
    subject(:command) { described_class.new(**default_params.merge(qty: 0)) }

    it 'fails with invalid_quantity' do
      result = command.call
      expect(result).to be_failure
      expect(result.reason).to eq('invalid_quantity')
    end
  end

  context 'when side is invalid' do
    subject(:command) { described_class.new(**default_params.merge(side: :sideways)) }

    it 'fails with invalid_side' do
      result = command.call
      expect(result).to be_failure
      expect(result.reason).to eq('invalid_side')
    end
  end

  context 'when segment is blank' do
    subject(:command) { described_class.new(**default_params.merge(segment: '')) }

    it 'fails with missing_segment' do
      result = command.call
      expect(result).to be_failure
      expect(result.reason).to eq('missing_segment')
    end
  end

  # ── No tracker required ─────────────────────────────────────────────────────

  context 'without a tracker (normal placement flow)' do
    it 'does not fail for missing tracker' do
      allow(gateway).to receive(:place_market).and_return({ success: true, order_id: 'X' })
      result = command.call
      expect(result).to be_success
    end
  end

  # ── Exception handling ──────────────────────────────────────────────────────

  describe '#call — unhandled exception' do
    before do
      allow(gateway).to receive(:place_market).and_raise(SocketError, 'connection refused')
    end

    it 'returns failure with command_exception' do
      result = command.call
      expect(result).to be_failure
      expect(result.reason).to eq('command_exception')
      expect(result.error).to be_a(SocketError)
    end
  end
end
