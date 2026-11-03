# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Positions::FinalPnl do
  describe '.from_exit_price' do
    it 'returns nil when exit price is blank' do
      expect(described_class.from_exit_price(
               entry_price: 100,
               quantity: 25,
               exit_price: nil
             )).to be_nil
    end

    it 'computes net pnl and decimal pct from exit price' do
      result = described_class.from_exit_price(
        entry_price: BigDecimal('150'),
        quantity: 25,
        exit_price: BigDecimal('127.5'),
        is_exited: true
      )

      gross = BigDecimal('-562.5')
      expected_net = BrokerFeeCalculator.net_pnl(gross, is_exited: true)
      capital = BigDecimal('3750')

      expect(result[:gross_pnl]).to eq(gross)
      expect(result[:pnl]).to eq(expected_net)
      expect(result[:pnl_pct]).to eq(expected_net / capital)
    end

    it 'defaults to long-side pnl when position_side is not given' do
      result = described_class.from_exit_price(
        entry_price: BigDecimal('100'),
        quantity: 25,
        exit_price: BigDecimal('120'),
        is_exited: true
      )

      expect(result[:gross_pnl]).to eq(BigDecimal('500'))
    end

    it 'inverts gross pnl for a short position (profit when price falls)' do
      result = described_class.from_exit_price(
        entry_price: BigDecimal('100'),
        quantity: 25,
        exit_price: BigDecimal('80'),
        position_side: 'short',
        is_exited: true
      )

      expect(result[:gross_pnl]).to eq(BigDecimal('500'))
    end

    it 'shows a short position losing when price rises' do
      result = described_class.from_exit_price(
        entry_price: BigDecimal('100'),
        quantity: 25,
        exit_price: BigDecimal('120'),
        position_side: 'short',
        is_exited: true
      )

      expect(result[:gross_pnl]).to eq(BigDecimal('-500'))
    end
  end

  describe 'statutory charges (segment given)' do
    let(:args) { { entry_price: BigDecimal('100'), quantity: 50, exit_price: BigDecimal('120'), is_exited: true } }

    it 'nets gross P&L against real buy-leg plus sell-leg charges, not the flat per-order fee' do
      result = described_class.from_exit_price(**args, segment: 'NSE_FNO')

      charges = Orders::ChargesCalculator.call(side: 'buy', quantity: 50, price: 100) +
                Orders::ChargesCalculator.call(side: 'sell', quantity: 50, price: 120)
      expect(result[:charges]).to eq(charges)
      expect(result[:pnl]).to eq(BigDecimal('1000') - charges)
      expect(charges).to be > BrokerFeeCalculator.fee_per_trade
    end

    it 'charges a short position the sell leg at entry and the buy leg at exit' do
      result = described_class.from_exit_price(**args, exit_price: BigDecimal('80'), position_side: 'short', segment: 'NSE_FNO')

      charges = Orders::ChargesCalculator.call(side: 'sell', quantity: 50, price: 100) +
                Orders::ChargesCalculator.call(side: 'buy', quantity: 50, price: 80)
      expect(result[:gross_pnl]).to eq(BigDecimal('1000'))
      expect(result[:charges]).to eq(charges)
    end

    it 'keeps the flat fee when no segment is given (estimates, live marks, legacy rows)' do
      result = described_class.from_exit_price(**args)

      expect(result[:charges]).to be_nil
      expect(result[:pnl]).to eq(BrokerFeeCalculator.net_pnl(BigDecimal('1000'), is_exited: true))
    end
  end

  describe '.for_tracker' do
    let(:base) { { entry_price: BigDecimal('100'), exit_price: BigDecimal('120'), quantity: 50, status: 'exited' } }

    it 'uses statutory charges only for trackers stamped with the statutory fee model' do
      stamped = create(:position_tracker, :paper, **base, meta: { 'fee_model' => 'statutory' })
      legacy = create(:position_tracker, :paper, **base, meta: {})

      expect(described_class.for_tracker(stamped)[:charges]).to be_present
      expect(described_class.for_tracker(legacy)[:charges]).to be_nil
    end
  end
end
