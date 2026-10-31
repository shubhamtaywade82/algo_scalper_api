# frozen_string_literal: true

require "rails_helper"

RSpec.describe Investing::Allocation::PolicyValidator do
  subject(:result) { described_class.call(mandate: mandate) }

  # Four sleeves summing to exactly 100; every group target sits strictly
  # inside its band — the minimal VALID mandate (A-POL-02).
  let(:base_mandate) do
    {
      allocation: {
        indian_large_cap: { group: :equity, target_pct: 25 },
        indian_mid_small_cap: { group: :equity,            target_pct: 10 },
        government_aaa_bonds: { group: :fixed_income,      target_pct: 15 },
        cash_liquid_funds: { group: :cash_alternatives, target_pct: 50 }
      },
      constraints: { max_single_stock_pct: 2.5, max_sector_pct: 12, max_illiquid_pct: 25 },
      rebalancing: {
        bands: {
          equity: { lower_pct: 30, upper_pct: 40 },
          fixed_income: { lower_pct: 10, upper_pct: 20 },
          cash_alternatives: { lower_pct: 40, upper_pct: 60 }
        },
        threshold_to_act_pct: 1.0
      },
      deployment: { equity_tranches: 3, deployment_weeks: 12 }
    }
  end

  context "with a valid mandate" do
    let(:mandate) { base_mandate }

    it { is_expected.to be_success }

    it "normalizes weights to BigDecimal (A-POL-02)" do
      expect(result.payload.dig(:normalized, "allocation",
                                "indian_large_cap", "target_pct")).to eq(BigDecimal("25"))
    end

    it "keeps constraints and rebalancing sections, string-keyed" do
      expect(result.payload.dig(:normalized, "constraints")).to include("max_sector_pct" => 12)
      expect(result.payload.dig(:normalized, "rebalancing")).to include("threshold_to_act_pct" => 1.0)
    end
  end

  context "when weights sum to 99.9999 (A-POL-01)" do
    let(:mandate) do
      base_mandate.tap { |m| m[:allocation][:cash_liquid_funds][:target_pct] = 49.9999 }
    end

    it "fails with the exact sum, never rounding through" do
      expect(result).to be_failure
      expect(result.errors.first).to eq(
        [:weights_do_not_sum_to_100, { sum: BigDecimal("99.9999") }]
      )
    end
  end

  context "when a group band excludes the group target (A-POL-03)" do
    let(:mandate) do
      m = base_mandate
      m[:allocation][:indian_large_cap][:target_pct] = 40 # equity sum 50 > upper 40
      m[:allocation][:cash_liquid_funds][:target_pct] = 35
      m
    end

    it "fails with band_excludes_target" do
      expect(result).to be_failure
      expect(result.errors.map(&:first)).to include(:band_excludes_target)
    end
  end

  context "when a sleeve references an unknown group" do
    let(:mandate) do
      base_mandate.tap do |m|
        m[:allocation][:cash_liquid_funds] = { group: :crypto, target_pct: 50 }
      end
    end

    it "fails with unknown_group_key" do
      expect(result.errors.map(&:first)).to include(:unknown_group_key)
    end
  end

  context "when single-stock cap exceeds sector cap (A-POL-04)" do
    let(:mandate) do
      base_mandate.tap do |m|
        m[:constraints] = { max_single_stock_pct: 15, max_sector_pct: 12 }
      end
    end

    it "fails with constraints_inconsistent" do
      expect(result.errors.map(&:first)).to include(:constraints_inconsistent)
    end
  end

  context "when a percentage is out of range" do
    let(:mandate) do
      base_mandate.tap do |m|
        m[:allocation][:government_aaa_bonds][:target_pct] = 0
        m[:allocation][:cash_liquid_funds][:target_pct] = 65
      end
    end

    it "fails with invalid_pct_range" do
      expect(result.errors.map(&:first)).to include(:invalid_pct_range)
    end
  end

  context "when the drift threshold is dust-sized" do
    let(:mandate) do
      base_mandate.tap { |m| m[:rebalancing][:threshold_to_act_pct] = 0.01 }
    end

    it "fails with threshold_too_small" do
      expect(result.errors.map(&:first)).to include(:threshold_too_small)
    end
  end

  context "when deployment is out of range" do
    let(:mandate) do
      base_mandate.tap { |m| m[:deployment] = { equity_tranches: 30, deployment_weeks: 12 } }
    end

    it "fails with deployment_out_of_range" do
      expect(result.errors.map(&:first)).to include(:deployment_out_of_range)
    end
  end

  context "when allocation is missing entirely" do
    let(:mandate) { { constraints: {} } }

    it "fails with allocation_missing" do
      expect(result.errors.map(&:first)).to eq([:allocation_missing])
    end
  end

  context "with the repo's balanced_v1 mandate from config/investing.yml" do
    let(:mandate) { Rails.application.config.x.investing[:mandates][:balanced_v1] }

    it { is_expected.to be_success }
  end
end
