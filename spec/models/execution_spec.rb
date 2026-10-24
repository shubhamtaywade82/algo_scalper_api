# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Execution do
  describe 'associations' do
    it { is_expected.to belong_to(:instrument) }
    it { is_expected.to belong_to(:position_tracker).optional }
  end

  describe 'validations' do
    it { is_expected.to validate_presence_of(:order_no) }
    it { is_expected.to validate_numericality_of(:quantity).is_greater_than(0) }

    it 'rejects a filled execution without a fill price' do
      execution = build(:execution, :pending)
      execution.status = 'filled'
      execution.fill_price = nil

      expect(execution).not_to be_valid
      expect(execution.errors[:fill_price]).to be_present
    end
  end

  describe '.record_from_order!' do
    let(:instrument) { create(:instrument, :nifty_call_option) }

    context 'with a paper gateway response (hash)' do
      let(:order) do
        {
          success: true,
          order_id: 'PAPER-abc123',
          paper: true,
          fill_price: 150.10,
          bid: 149.80,
          ask: 150.05,
          requested_price: 150.00
        }
      end

      it 'records a filled paper execution with bid/ask and slippage' do
        execution = described_class.record_from_order!(
          order: order, instrument: instrument, side: :buy, quantity: 75,
          purpose: :entry, requested_price: 150.00
        )

        expect(execution).to be_persisted
        expect(execution).to be_paper
        expect(execution).to be_confirmed
        expect(execution.order_no).to eq('PAPER-abc123')
        expect(execution.fill_price.to_f).to eq(150.10)
        expect(execution.bid.to_f).to eq(149.80)
        expect(execution.ask.to_f).to eq(150.05)
        # buy slippage measured against the ask
        expect(execution.slippage.to_f).to eq(0.05)
        expect(execution.filled_at).to be_present
      end
    end

    context 'with a live gateway response (no immediate fill)' do
      let(:order) { double('DhanOrder', order_id: 'DHAN-98765') }

      it 'records a pending live execution' do
        execution = described_class.record_from_order!(
          order: order, instrument: instrument, side: :buy, quantity: 75,
          purpose: :entry, requested_price: 150.00
        )

        expect(execution).to be_persisted
        expect(execution).to be_live
        expect(execution.status).to eq('pending')
        expect(execution.fill_price).to be_nil
        expect(execution.filled_at).to be_nil
      end
    end

    it 'returns nil (and does not raise) when the order carries no order id' do
      expect(
        described_class.record_from_order!(
          order: { success: false, paper: true }, instrument: instrument,
          side: :buy, quantity: 75
        )
      ).to be_nil
    end
  end

  describe '#confirm!' do
    it 'stamps the fill on a pending live execution' do
      execution = create(:execution, :pending, :live)

      execution.confirm!(fill_price: 151.20, fees: 20)

      expect(execution.reload).to be_confirmed
      expect(execution.fill_price.to_f).to eq(151.20)
      expect(execution.fees.to_f).to eq(20)
    end
  end
end
