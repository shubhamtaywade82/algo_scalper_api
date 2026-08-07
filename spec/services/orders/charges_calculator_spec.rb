# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Orders::ChargesCalculator do
  describe '.call' do
    it 'computes buy-side charges (brokerage, exchange txn, GST, stamp duty, SEBI — no STT)' do
      result = described_class.call(side: 'buy', quantity: 50, price: 150.0, segment: 'NSE_FNO')

      expect(result).to eq(BigDecimal('28.523'))
    end

    it 'computes sell-side charges (brokerage, STT, exchange txn, GST, SEBI — no stamp duty)' do
      result = described_class.call(side: 'sell', quantity: 50, price: 200.0, segment: 'NSE_FNO')

      expect(result).to eq(BigDecimal('31.114'))
    end

    it 'charges scale with turnover (price x quantity)' do
      small = described_class.call(side: 'buy', quantity: 25, price: 100.0, segment: 'NSE_FNO')
      large = described_class.call(side: 'buy', quantity: 250, price: 100.0, segment: 'NSE_FNO')

      expect(large).to be > small
    end

    it 'is symbol/string side-agnostic' do
      expect(described_class.call(side: :buy, quantity: 50, price: 150.0)).to eq(described_class.call(side: 'buy', quantity: 50, price: 150.0))
    end

    it 'returns just the brokerage-derived floor for zero turnover' do
      result = described_class.call(side: 'buy', quantity: 0, price: 150.0)

      expect(result).to eq(BigDecimal('20.0') + (BigDecimal('20.0') * described_class::GST_PCT))
    end
  end
end
