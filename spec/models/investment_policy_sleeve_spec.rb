# frozen_string_literal: true

require "rails_helper"

RSpec.describe InvestmentPolicySleeve do
  describe "associations" do
    it { is_expected.to belong_to(:investment_policy) }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:sleeve_key) }
    it { is_expected.to allow_value("indian_large_cap").for(:sleeve_key) }
    it { is_expected.not_to allow_value("Indian Large-Cap").for(:sleeve_key) }
    it { is_expected.to validate_numericality_of(:target_pct).is_greater_than(0).is_less_than_or_equal_to(100) }
  end

  describe "uniqueness per policy" do
    it "rejects a duplicate sleeve key within one policy" do
      policy = create(:investment_policy)
      create(:investment_policy_sleeve, investment_policy: policy, sleeve_key: "equity")

      sleeve = build(:investment_policy_sleeve, investment_policy: policy, sleeve_key: "equity")
      expect(sleeve).not_to be_valid
    end
  end
end
