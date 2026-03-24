# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Smc::StructureEngine do
  it 'returns neutral trend when data is thin' do
    series = build(:candle_series, :five_minute)
    state = described_class.new(series).call

    expect(state.trend).to eq(:neutral)
  end
end
