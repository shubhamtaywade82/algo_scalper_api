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
  end
end
