# frozen_string_literal: true

require "rails_helper"

RSpec.describe InvestmentLot do
  subject(:lot) { build(:investment_lot) }

  it { is_expected.to belong_to(:investment_holding).inverse_of(:investment_lots) }

  it "rejects a non-positive quantity" do
    lot.quantity = 0
    expect(lot).not_to be_valid
  end

  it "rejects remaining_quantity above quantity" do
    lot.quantity = 50
    lot.remaining_quantity = 60
    expect(lot).not_to be_valid
  end

  it "requires acquired_on (FIFO anchor)" do
    lot.acquired_on = nil
    expect(lot).not_to be_valid
  end

  it "restricts lot_source to known values" do
    lot.lot_source = "binocular"
    expect(lot).not_to be_valid
    expect(lot.errors[:lot_source]).to be_present
  end

  describe ".fifo scope" do
    it "orders by (acquired_on, id) and excludes exhausted lots" do
      holding = create(:investment_holding)
      oldest = create(:investment_lot, :older, investment_holding: holding)
      exhausted = create(:investment_lot, :partially_consumed, investment_holding: holding,
                                                               acquired_on: 70.days.ago,
                                                               remaining_quantity: 0)
      newest = create(:investment_lot, investment_holding: holding)

      ids = holding.investment_lots.fifo.map(&:id)
      expect(ids).to eq([oldest.id, newest.id])
      expect(ids).not_to include(exhausted.id)
    end
  end

  it "knows when it is fully consumed" do
    expect(build(:investment_lot, remaining_quantity: 0)).to be_fully_consumed
    expect(build(:investment_lot, remaining_quantity: 5)).not_to be_fully_consumed
  end
end
