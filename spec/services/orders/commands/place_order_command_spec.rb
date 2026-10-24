# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Orders::Commands::PlaceOrderCommand do
  subject(:command) { described_class.new(**default_params) }

  let(:gateway) { instance_double(Orders::GatewayPaper) }

  # tracker is intentionally absent — it doesn't exist at placement time
  let(:default_params) do
    {
      gateway: gateway,
      side: :buy,
      segment: 'NSE_FNO',
      security_id: '12345',
      qty: 50,
      meta: { index_key: 'NIFTY' }
    }
  end

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

  # ── Paper gateway (paper: true with explicit success) ────────────────────

  describe '#call — paper gateway response' do
    before do
      allow(gateway).to receive(:place_market).and_return(
        { success: true, paper: true, order_id: 'PAPER-abc123' }
      )
    end

    it 'treats a successful paper response as success' do
      result = command.call
      expect(result).to be_success
      expect(result.payload[:order_id]).to eq('PAPER-abc123')
      expect(result.payload[:paper]).to be true
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

  # ── Paper gateway failure must not masquerade as success (regression) ───────
  # GatewayPaper's rescue path returns {success: false, error: ..., paper: true}.
  # A tracker must never be created off a placement that actually failed.
  describe '#call — paper gateway failure' do
    before do
      allow(gateway).to receive(:place_market).and_return(
        { success: false, error: 'insufficient funds', paper: true }
      )
    end

    it 'returns failure even though paper: true is present' do
      result = command.call
      expect(result).to be_failure
      expect(result.reason).to eq('broker_rejected')
    end
  end

  describe '#call — paper gateway response missing success key entirely' do
    before do
      allow(gateway).to receive(:place_market).and_return(
        { paper: true, order_id: 'PAPER-abc123' }
      )
    end

    it 'does not treat an ambiguous response as success' do
      result = command.call
      expect(result).to be_failure
      expect(result.reason).to eq('broker_rejected')
    end
  end

  # ── Validation failures ─────────────────────────────────────────────────────

  context 'when gateway is nil' do
    subject(:command) { described_class.new(**default_params, gateway: nil) }

    it 'fails with missing_gateway' do
      result = command.call
      expect(result).to be_failure
      expect(result.reason).to eq('missing_gateway')
    end
  end

  context 'when qty is zero' do
    subject(:command) { described_class.new(**default_params, qty: 0) }

    it 'fails with invalid_quantity' do
      result = command.call
      expect(result).to be_failure
      expect(result.reason).to eq('invalid_quantity')
    end
  end

  context 'when qty is NaN' do
    subject(:command) { described_class.new(**default_params, qty: Float::NAN) }

    it 'does not raise during initialization' do
      expect { command }.not_to raise_error
    end

    it 'fails with invalid_quantity' do
      result = command.call
      expect(result).to be_failure
      expect(result.reason).to eq('invalid_quantity')
    end
  end

  context 'when side is invalid' do
    subject(:command) { described_class.new(**default_params, side: :sideways) }

    it 'fails with invalid_side' do
      result = command.call
      expect(result).to be_failure
      expect(result.reason).to eq('invalid_side')
    end
  end

  context 'when segment is blank' do
    subject(:command) { described_class.new(**default_params, segment: '') }

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
