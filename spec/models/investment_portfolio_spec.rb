# frozen_string_literal: true

require "rails_helper"

RSpec.describe InvestmentPortfolio do
  describe "associations" do
    it { is_expected.to have_many(:policies).class_name("InvestmentPolicy").dependent(:destroy) }
    it { is_expected.to have_many(:holdings).class_name("InvestmentHolding").dependent(:destroy) }
  end

  describe "validations" do
    subject(:portfolio) { build(:investment_portfolio) }

    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_uniqueness_of(:name).case_insensitive }
    it { is_expected.to validate_inclusion_of(:base_currency).in_array(%w[INR USD]) }

    it do
      expect(portfolio).to validate_numericality_of(:investment_horizon_years)
        .is_greater_than_or_equal_to(1)
        .is_less_than_or_equal_to(50)
        .only_integer
    end

    it { is_expected.to validate_inclusion_of(:risk_profile).in_array(%w[conservative balanced growth]) }
    it { is_expected.to validate_inclusion_of(:status).in_array(%w[active paused closed]) }
    it { is_expected.to validate_inclusion_of(:broker_linkage).in_array(%w[dhan manual external]) }
  end

  describe "#active_policy" do
    it "returns the single active policy" do
      portfolio = create(:investment_portfolio)
      active = create(:investment_policy, :active, investment_portfolio: portfolio, version: 2)
      create(:investment_policy, :draft, investment_portfolio: portfolio, version: 3)

      expect(portfolio.active_policy).to eq(active)
    end

    it "returns nil when no policy is active" do
      portfolio = create(:investment_portfolio)
      create(:investment_policy, :draft, investment_portfolio: portfolio)

      expect(portfolio.active_policy).to be_nil
    end
  end
end
