# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Orders::Commands::CommandResult do
  # ── Factory helpers ─────────────────────────────────────────────────────────

  describe '.success' do
    subject(:result) { described_class.success(payload: { order_id: 'ABC' }, command_class: 'PlaceOrderCommand') }

    it { expect(result).to be_success }
    it { expect(result).not_to be_failure }
    it { expect(result.payload[:order_id]).to eq('ABC') }
    it { expect(result.reason).to eq('ok') }
    it { expect(result.command_class).to eq('PlaceOrderCommand') }
    it { expect(result.executed_at).to be_a(ActiveSupport::TimeWithZone).or be_a(Time) }
  end

  describe '.failure' do
    subject(:result) { described_class.failure('broker_rejected', error: error, payload: { raw: {} }) }

    let(:error) { RuntimeError.new('boom') }

    it { expect(result).to be_failure }
    it { expect(result).not_to be_success }
    it { expect(result.reason).to eq('broker_rejected') }
    it { expect(result.error).to eq(error) }
    it { expect(result.payload[:raw]).to eq({}) }
  end

  # ── Serialisation ───────────────────────────────────────────────────────────

  describe '#to_h' do
    subject(:h) { described_class.success(payload: { x: 1 }).to_h }

    it 'includes expected keys' do
      expect(h.keys).to include(:success, :reason, :payload, :error, :executed_at, :command)
    end

    it 'serialises error message as string' do
      result = described_class.failure('err', error: RuntimeError.new('oops'))
      expect(result.to_h[:error]).to eq('oops')
    end

    it 'error is nil for successful results' do
      expect(h[:error]).to be_nil
    end
  end
end
