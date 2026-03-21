# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Derivatives::AtmOptions do
  let!(:in_range_call) do
    create(
      :derivative,
      :call_option,
      underlying_symbol: 'NIFTY',
      expiry_date: Date.current,
      strike_price: 25_000
    )
  end

  let!(:in_range_put) do
    create(
      :derivative,
      :put_option,
      underlying_symbol: 'NIFTY',
      expiry_date: Date.current,
      strike_price: 25_050
    )
  end

  let!(:next_expiry_option) do
    create(
      :derivative,
      :call_option,
      underlying_symbol: 'NIFTY',
      expiry_date: Date.current + 1.day,
      strike_price: 25_000
    )
  end

  let!(:out_of_range_option) do
    create(
      :derivative,
      :call_option,
      underlying_symbol: 'NIFTY',
      expiry_date: Date.current,
      strike_price: 26_000
    )
  end

  let(:result) { described_class.call(symbol: 'NIFTY', atm: 25_000, range: 100) }

  describe '.call' do
    it 'includes options within the configured strike range' do
      expect(result).to include(in_range_call, in_range_put)
      expect(result).not_to include(out_of_range_option)
    end

    it 'returns only current expiry options' do
      expect(result).not_to include(next_expiry_option)
      expect(result.pluck(:expiry_date).uniq).to eq([Date.current])
    end
  end
end
