# frozen_string_literal: true

require "rails_helper"

RSpec.describe AllocationSleeve do
  let(:portfolio) { InvestmentPortfolio.create!(name: "sleeve-portfolio", mode: "paper") }
  let(:policy) do
    InvestmentPolicy.create!(
      investment_portfolio: portfolio, mandate_version: "balanced_v1",
      status: "draft", rebalance_band_min_pct: 50, rebalance_band_max_pct: 60
    )
  end

  it "enforces sleeve_key uniqueness within a policy" do
    described_class.create!(investment_policy: policy, sleeve_key: "cash",
                            sleeve_name: "Cash", asset_class: "cash", target_weight_pct: 5)
    dup = described_class.new(investment_policy: policy, sleeve_key: "cash",
                              sleeve_name: "Cash", asset_class: "cash", target_weight_pct: 5)
    expect(dup).not_to be_valid
    expect(dup.errors[:sleeve_key]).to be_present
  end

  it "rejects a weight outside (0,100]" do
    sleeve = described_class.new(investment_policy: policy, sleeve_key: "x",
                                 sleeve_name: "X", asset_class: "equity",
                                 target_weight_pct: 101)
    expect(sleeve).not_to be_valid
  end

  it "rejects an unknown asset class" do
    sleeve = described_class.new(investment_policy: policy, sleeve_key: "y",
                                 sleeve_name: "Y", asset_class: "paintings",
                                 target_weight_pct: 5)
    expect(sleeve).not_to be_valid
  end

  it "orders by display_order then id" do
    a = described_class.create!(investment_policy: policy, sleeve_key: "b",
                                sleeve_name: "B", asset_class: "cash", target_weight_pct: 5, display_order: 2)
    b = described_class.create!(investment_policy: policy, sleeve_key: "a",
                                sleeve_name: "A", asset_class: "cash", target_weight_pct: 5, display_order: 1)
    expect(policy.allocation_sleeves.ordered).to eq([b, a])
  end
end
