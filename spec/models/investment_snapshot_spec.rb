# frozen_string_literal: true

require "rails_helper"

RSpec.describe InvestmentSnapshot do
  subject(:snapshot) { build(:investment_snapshot) }

  it { is_expected.to belong_to(:investment_portfolio) }

  it "is unique per (portfolio, as_of_date) — model + DB enforcement" do
    snapshot.save!
    dup = build(:investment_snapshot,
                investment_portfolio: snapshot.investment_portfolio,
                as_of_date: snapshot.as_of_date)
    expect(dup).not_to be_valid
    # DB-level: bypass the model validation and hit the unique index directly
    expect { dup.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it "rejects negative values" do
    snapshot.total_value = -1
    expect(snapshot).not_to be_valid
  end

  it "allows nil xirr (Phase 5 computes it later)" do
    expect(build(:investment_snapshot, xirr: nil)).to be_valid
  end
end
