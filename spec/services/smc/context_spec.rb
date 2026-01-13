# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Smc::Context do
  it 'exposes detector instances' do
    series = build(:candle_series, :five_minute, :with_candles)
    ctx = described_class.new(series)

    expect(ctx.structure).to be_a(Smc::Detectors::Structure)
    expect(ctx.liquidity).to be_a(Smc::Detectors::Liquidity)
    expect(ctx.order_blocks).to be_a(Smc::Detectors::OrderBlocks)
    expect(ctx.fvg).to be_a(Smc::Detectors::Fvg)
    expect(ctx.pd).to be_a(Smc::Detectors::PremiumDiscount)
  end
end
