# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Entries::Guards::RiskPolicyGuard do
  describe '.call' do
    let(:context) do
      {
        index_cfg: { key: 'NIFTY' },
        pick: { symbol: 'NIFTY24MAR24000CE' },
        quantity: 65,
        ltp: 150.0,
        lot_size: 65
      }
    end
    let(:risk_policy_double) { instance_double(Policies::RiskPolicy) }

    before do
      allow(Policies::RiskPolicy).to receive(:new).and_return(risk_policy_double)
    end

    context 'when risk policy permits' do
      before do
        allow(risk_policy_double).to receive(:permitted?).and_return(true)
      end

      it 'allows entry' do
        result = described_class.call(context)
        expect(result).to eq(Entries::EntryGuardPipeline::PASS)
      end

      it 'initializes RiskPolicy with correct attributes' do
        described_class.call(context)

        expect(Policies::RiskPolicy).to have_received(:new).with(
          index_key: 'NIFTY',
          proposed_qty: 65,
          entry_price: 150.0,
          lot_size: 65
        )
      end
    end

    context 'when risk policy does not permit' do
      before do
        allow(risk_policy_double).to receive_messages(permitted?: false, reasons: %w[per_trade_risk_exceeded max_exposure_exceeded])
      end

      it 'blocks entry' do
        result = described_class.call(context)
        expect(result).to include(blocked: /per_trade_risk_exceeded.*max_exposure_exceeded/)
      end
    end

    context 'with nil ltp' do
      let(:context) do
        {
          index_cfg: { key: 'BANKNIFTY' },
          pick: { symbol: 'BANKNIFTY24MAR50000CE' },
          quantity: 30,
          ltp: nil,
          lot_size: 15
        }
      end

      before do
        allow(risk_policy_double).to receive(:permitted?).and_return(true)
      end

      it 'converts nil ltp to 0.0' do
        described_class.call(context)

        expect(Policies::RiskPolicy).to have_received(:new).with(
          index_key: 'BANKNIFTY',
          proposed_qty: 30,
          entry_price: 0.0,
          lot_size: 15
        )
      end

      it 'allows entry if policy permits' do
        result = described_class.call(context)
        expect(result).to eq(Entries::EntryGuardPipeline::PASS)
      end
    end

    context 'with nil quantity' do
      let(:context) do
        {
          index_cfg: { key: 'NIFTY' },
          pick: { symbol: 'NIFTY24MAR24000CE' },
          quantity: nil,
          ltp: 150.0,
          lot_size: 65
        }
      end

      before do
        allow(risk_policy_double).to receive(:permitted?).and_return(true)
      end

      it 'passes nil quantity to RiskPolicy' do
        described_class.call(context)

        expect(Policies::RiskPolicy).to have_received(:new).with(
          index_key: 'NIFTY',
          proposed_qty: nil,
          entry_price: 150.0,
          lot_size: 65
        )
      end
    end
  end
end
