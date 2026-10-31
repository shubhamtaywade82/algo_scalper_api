# frozen_string_literal: true

require "rails_helper"

RSpec.describe InvestmentPolicy do
  describe "associations" do
    it { is_expected.to belong_to(:investment_portfolio) }
    it { is_expected.to have_many(:sleeves).class_name("InvestmentPolicySleeve").dependent(:destroy) }
  end

  describe "validations" do
    it { is_expected.to validate_numericality_of(:version).is_greater_than_or_equal_to(1).only_integer }
    it { is_expected.to validate_inclusion_of(:status).in_array(%w[draft active superseded]) }
    it { is_expected.to validate_presence_of(:effective_from) }
  end

  describe "one active policy per portfolio (DB-enforced, A-MDL-02)" do
    it "raises on a second active policy" do
      portfolio = create(:investment_portfolio)
      create(:investment_policy, :active, investment_portfolio: portfolio, version: 1)

      expect do
        create(:investment_policy, :active, investment_portfolio: portfolio, version: 2)
      end.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "allows a draft alongside the active version (A-MDL-03)" do
      portfolio = create(:investment_portfolio)
      create(:investment_policy, :active, investment_portfolio: portfolio, version: 1)
      draft = create(:investment_policy, :draft, investment_portfolio: portfolio, version: 2)

      expect(draft.version).to eq(2)
    end

    it "rejects duplicate version numbers for the same portfolio" do
      portfolio = create(:investment_portfolio)
      create(:investment_policy, :draft, investment_portfolio: portfolio, version: 1)

      expect do
        create(:investment_policy, :draft, investment_portfolio: portfolio, version: 1)
      end.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end

  describe "#sleeve_target_sum" do
    it "sums sleeve targets exactly" do
      policy = create(:investment_policy, :with_balanced_sleeves)

      expect(policy.sleeve_target_sum).to eq(BigDecimal("100"))
    end
  end

  describe "#group_bands and #threshold_to_act_pct" do
    it "reads band configuration from the rebalancing jsonb" do
      policy = create(:investment_policy)

      expect(policy.group_bands["equity"]).to eq({ "lower_pct" => 50, "upper_pct" => 60 })
      expect(policy.threshold_to_act_pct).to eq(BigDecimal("1.0"))
    end

    it "defaults the threshold to 1.0pp when unconfigured" do
      policy = create(:investment_policy, rebalancing: {})

      expect(policy.threshold_to_act_pct).to eq(BigDecimal("1.0"))
    end
  end
end
