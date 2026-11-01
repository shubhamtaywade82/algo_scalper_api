# frozen_string_literal: true

require "rails_helper"

RSpec.describe InvestmentPolicy do
  let(:portfolio) { InvestmentPortfolio.create!(name: "spec-portfolio", mode: "paper", cash_balance: 100_000) }

  def build_policy(status: "draft", sleeves: [25, 10, 10, 10, 15, 10, 5, 7, 5, 3])
    policy = described_class.new(
      investment_portfolio: portfolio,
      mandate_version: "balanced_v1",
      status: status,
      rebalance_band_min_pct: 50,
      rebalance_band_max_pct: 60
    )
    keys = %w[large_cap_core mid_small_cap global_equity thematic_tech_clean
              govt_aaa_bonds short_duration_debt reit_invit infra cash gold_silver]
    classes = %w[equity equity equity equity debt debt reit infra cash gold]
    sleeves.each_with_index do |weight, i|
      policy.allocation_sleeves.build(
        sleeve_key: keys[i], sleeve_name: keys[i], asset_class: classes[i],
        target_weight_pct: weight, display_order: i
      )
    end
    policy
  end

  describe "one active policy per portfolio (TDD §16 A1.3)" do
    it "keeps the DB-level partial unique index guard" do
      build_policy(status: "active").save!(validate: false)
      expect { build_policy(status: "active").save!(validate: false) }
        .to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "allows draft policies alongside an active one" do
      build_policy(status: "active").save!(validate: false)
      expect { build_policy(status: "draft").save!(validate: false) }.not_to raise_error
    end
  end

  describe "sleeve weight sum for active policies (TDD §16 A1.2)" do
    it "is invalid when sleeves do not sum to exactly 100" do
      policy = build_policy(status: "active", sleeves: [25, 10, 10, 10, 15, 10, 5, 7, 5, 2.5])
      expect(policy).not_to be_valid
      expect(policy.errors[:base].join).to include("sum to exactly 100")
    end

    it "is valid when sleeves sum to exactly 100" do
      expect(build_policy(status: "active")).to be_valid
    end

    it "does not apply the sum rule to draft policies" do
      policy = build_policy(status: "draft", sleeves: [25, 10, 10, 10, 15, 10, 5, 7, 5, 2.5])
      expect(policy).to be_valid
    end
  end

  describe "field validations" do
    it "requires a mandate version" do
      policy = build_policy
      policy.mandate_version = nil
      expect(policy).not_to be_valid
      expect(policy.errors[:mandate_version]).to be_present
    end

    it "rejects an unknown status" do
      policy = build_policy
      policy.status = "paused"
      expect(policy).not_to be_valid
      expect(policy.errors[:status]).to be_present
    end

    it "rejects an inverted band" do
      policy = build_policy
      policy.rebalance_band_min_pct = 60
      policy.rebalance_band_max_pct = 50
      expect(policy).not_to be_valid
      expect(policy.errors[:rebalance_band_min_pct]).to be_present
    end
  end

  describe "#equity_band" do
    it "returns the band pair" do
      expect(build_policy.equity_band).to eq([BigDecimal("50"), BigDecimal("60")])
    end
  end
end

