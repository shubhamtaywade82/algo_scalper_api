# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Adapters::Margin::DhanMarginAdapter do
  subject(:adapter) { described_class.new }

  let(:margin_result) { double(total_margin: 12_345.67) } # rubocop:disable RSpec/VerifiedDoubles -- gem's attribute DSL isn't introspectable

  before do
    allow(DhanHQ::Models::Margin).to receive(:calculate).and_return(margin_result)
  end

  it 'returns the total margin for the requested lot as a BigDecimal' do
    result = adapter.margin_for(segment: 'NSE_FNO', security_id: '12345', quantity: 75, price: 120.5)

    expect(result).to eq(BigDecimal('12345.67'))
    expect(DhanHQ::Models::Margin).to have_received(:calculate).with(
      hash_including(exchange_segment: 'NSE_FNO', transaction_type: 'SELL', quantity: 75, product_type: 'MARGIN')
    )
  end

  it 'returns nil and logs when the calculator call raises' do
    allow(DhanHQ::Models::Margin).to receive(:calculate).and_raise(StandardError, 'boom')

    expect(adapter.margin_for(segment: 'NSE_FNO', security_id: '12345', quantity: 75, price: 120.5)).to be_nil
  end
end
