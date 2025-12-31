# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Smc::Detectors::Liquidity do
  it 'wraps buy-side and sell-side liquidity grabs' do
    series = instance_double('CandleSeries')
    allow(series).to receive(:liquidity_grab_up?).and_return(true)
    allow(series).to receive(:liquidity_grab_down?).and_return(false)

    detector = described_class.new(series)
    expect(detector.buy_side_taken?).to be(true)
    expect(detector.sell_side_taken?).to be(false)
    expect(detector.sweep_direction).to eq(:buy_side)
  end
end

