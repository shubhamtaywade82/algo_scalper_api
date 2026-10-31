# frozen_string_literal: true

require "rails_helper"

RSpec.describe Investing::Allocation::Calculator do
  subject(:calculations) { described_class.call(policy: policy, valuation: valuation) }

  let(:portfolio) { create(:investment_portfolio) }
  let(:policy)    { create(:investment_policy, :balanced, investment_portfolio: portfolio) }

  # The strategy-review worked example (TDD §7.2, A-ALC-04): ₹10,00,000 NAV,
  # equity 62% vs target 55% with a 50–60% band → group breach.
  let(:valuation) do
    Investing::ValuationReport.new(
      total_value: 1_000_000,
      sleeve_values: {
        indian_large_cap: 350_000,
        indian_mid_small_cap: 150_000,
        global_equity: 60_000,
        technology_clean_energy: 60_000,
        government_aaa_bonds: 200_000,
        short_duration_debt: 0,
        reits_invits: 40_000,
        infrastructure_funds: 60_000,
        cash_liquid_funds: 80_000,
        gold_silver_etfs: 0
      }
    )
  end

  it "computes per-sleeve actuals and targets on BigDecimal (A-ALC-01)" do
    large = calculations.sleeves.find { |s| s.sleeve_key == "indian_large_cap" }

    expect(large.target_pct).to eq(BigDecimal("25"))
    expect(large.actual_pct).to eq(BigDecimal("35.0"))
    expect(large.drift_pct).to eq(BigDecimal("10.0"))
    expect(large.target_value).to eq(BigDecimal("250000.0"))
    expect(large.drift_value).to eq(BigDecimal("100000.0"))
  end

  it "aggregates groups and flags the equity band breach (A-ALC-04)" do
    equity = calculations.groups.find { |g| g.group_key == "equity" }

    expect(equity.target_pct).to eq(BigDecimal("55.0"))
    expect(equity.actual_pct).to eq(BigDecimal("62.0"))
    expect(equity.drift_pct).to eq(BigDecimal("7.0"))
    expect(equity).not_to be_within_band
  end

  it "marks groups inside their bands (inclusive bounds)" do
    fixed_income = calculations.groups.find { |g| g.group_key == "fixed_income" }

    expect(fixed_income.actual_pct).to eq(BigDecimal("20.0"))
    expect(fixed_income).to be_within_band
  end

  it "propagates the group band verdict onto each member sleeve" do
    large = calculations.sleeves.find { |s| s.sleeve_key == "indian_large_cap" }

    expect(large.band_lower_pct).to eq(BigDecimal("50"))
    expect(large.band_upper_pct).to eq(BigDecimal("60"))
    expect(large).not_to be_within_band
  end

  it "reports zero actuals for empty sleeves (A-ALC-02)" do
    gold = calculations.sleeves.find { |s| s.sleeve_key == "gold_silver_etfs" }

    expect(gold.actual_value).to eq(BigDecimal("0"))
    expect(gold.actual_pct).to eq(BigDecimal("0"))
    expect(gold.drift_pct).to eq(BigDecimal("-3.0"))
  end

  it "keeps a group ordering that matches sleeve display order" do
    expect(calculations.groups.map(&:group_key))
      .to eq(%w[equity fixed_income real_assets cash_alternatives])
  end

  describe "edge cases" do
    it "returns all-zero actuals for an empty portfolio (A-ALC-02)" do
      empty = described_class.call(
        policy: policy,
        valuation: Investing::ValuationReport.new(total_value: 0)
      )

      expect(empty.total_value).to eq(BigDecimal("0"))
      expect(empty.sleeves.map(&:actual_pct)).to all(eq(BigDecimal("0")))
      expect(empty.unclassified_pct).to eq(BigDecimal("0"))
    end

    it "aggregates unclassified holdings separately (A-ALC-03)" do
      calc = described_class.call(
        policy: policy,
        valuation: Investing::ValuationReport.new(
          total_value: 100,
          sleeve_values: { indian_large_cap: 90 },
          unclassified_value: 10
        )
      )

      expect(calc.unclassified_value).to eq(BigDecimal("10"))
      expect(calc.unclassified_pct).to eq(BigDecimal("10.0"))
    end

    it "ignores sleeve values the policy does not define" do
      calc = described_class.call(
        policy: policy,
        valuation: Investing::ValuationReport.new(
          total_value: 100,
          sleeve_values: { indian_large_cap: 90, not_in_policy: 10 }
        )
      )

      expect(calc.sleeves.map(&:sleeve_key)).not_to include("not_in_policy")
      expect(calc.groups.sum(&:actual_pct)).to eq(BigDecimal("90.0"))
    end
  end
end
