# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Entries::DecisionRejection do
  subject(:rejection) do
    described_class.new(
      code: :premium_above_limit,
      category: :risk,
      message: 'Option premium exceeds max limit',
      details: { premium: 248, limit: 220 }
    )
  end

  it 'returns approved? as false' do
    expect(rejection.approved?).to be false
  end

  it 'returns rejected? as true' do
    expect(rejection.rejected?).to be true
  end

  it 'serializes to machine-readable hash' do
    expect(rejection.to_h).to eq(
      approved: false,
      code: :premium_above_limit,
      category: :risk,
      message: 'Option premium exceeds max limit',
      details: { premium: 248, limit: 220 }
    )
  end
end
