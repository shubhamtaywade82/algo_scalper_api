# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Smc::Detectors::PremiumDiscount do
  it 'computes equilibrium and premium/discount state' do
    series = build(:candle_series, :five_minute)
    series.add_candle(build(:candle, high: 110, low: 90, close: 95))
    series.add_candle(build(:candle, high: 120, low: 80, close: 115))

    detector = described_class.new(series)
    expect(detector.equilibrium).to eq(100.0)
    expect(detector.premium?).to be(true)
    expect(detector.discount?).to be(false)
  end
end

