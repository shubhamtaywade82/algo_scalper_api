# frozen_string_literal: true

require "rails_helper"

RSpec.describe Investing::Allocation::DriftAnalyzer do
  subject(:report) { described_class.call(calculations: calculations, policy: policy) }

  let(:portfolio)    { create(:investment_portfolio) }
  let(:policy)       { create(:investment_policy, :balanced, investment_portfolio: portfolio) }
  let(:calculations) { Investing::Allocation::Calculator.call(policy: policy, valuation: valuation) }

  # Worked example: equity 62% vs 55% target, band 50–60% → breach (A-ALC-04).
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

  it "requires a rebalance on a group band breach" do
    expect(report).to be_rebalance_required

    trigger = report.triggers.find { |t| t.kind == :group_band_breach }
    expect(trigger.key).to eq("equity")
    expect(trigger.actual_pct).to eq(BigDecimal("62.0"))
    expect(trigger.target_pct).to eq(BigDecimal("55.0"))
    expect(trigger.drift_pct).to eq(BigDecimal("7.0"))
  end

  it "also emits sleeve-threshold triggers at or above 1.0pp (A-ALC-05)" do
    sleeve_keys = report.triggers.select { |t| t.kind == :sleeve_threshold }.map(&:key)

    expect(sleeve_keys).to include("indian_large_cap", "short_duration_debt")
  end

  it "ranks overweights by drift value with display order as tiebreaker" do
    expect(report.overweights.map(&:sleeve_key))
      .to eq(%w[indian_large_cap indian_mid_small_cap government_aaa_bonds cash_liquid_funds])
  end

  it "ranks underweights by absolute drift value" do
    expect(report.underweights.map(&:sleeve_key))
      .to eq(%w[short_duration_debt global_equity technology_clean_energy
                gold_silver_etfs reits_invits infrastructure_funds])
  end

  it "reports the largest absolute sleeve drift" do
    expect(report.max_abs_drift_pp).to eq(BigDecimal("10.0"))
  end

  it "renders the deterministic narrative block (A-ALC-06)" do
    expect(report.narrative).to include("PORTFOLIO REBALANCE REQUIRED")
    expect(report.narrative).to include("Equity: target 55.0%, actual 62.0%, drift +7.0pp, band 50.0–60.0% — BREACHED")
    expect(report.narrative).to include("Fixed income: target 25.0%, actual 20.0%, drift -5.0pp, band 20.0–30.0% — OK")
  end

  it "produces identical output for identical inputs (determinism)" do
    again = described_class.call(calculations: calculations, policy: policy)

    expect(again.narrative).to eq(report.narrative)
    expect(again.triggers).to eq(report.triggers)
  end

  context "when the portfolio sits at target" do
    let(:valuation) do
      Investing::ValuationReport.new(
        total_value: 1_000_000,
        sleeve_values: {
          indian_large_cap: 250_000,
          indian_mid_small_cap: 100_000,
          global_equity: 100_000,
          technology_clean_energy: 100_000,
          government_aaa_bonds: 150_000,
          short_duration_debt: 100_000,
          reits_invits: 50_000,
          infrastructure_funds: 70_000,
          cash_liquid_funds: 50_000,
          gold_silver_etfs: 30_000
        }
      )
    end

    it "does not require a rebalance" do
      expect(report).not_to be_rebalance_required
      expect(report.triggers).to be_empty
      expect(report.narrative).to include("PORTFOLIO IN BALANCE")
    end
  end

  context "when drift is positive but under every threshold (A-ALC-05)" do
    let(:valuation) do
      Investing::ValuationReport.new(
        total_value: 1_000_000,
        sleeve_values: {
          indian_large_cap: 254_000, # +0.4pp
          indian_mid_small_cap: 102_000, # +0.2pp
          global_equity: 98_000, # -0.2pp
          technology_clean_energy: 101_000, # +0.1pp
          government_aaa_bonds: 149_000, # -0.1pp
          short_duration_debt: 101_000, # +0.1pp
          reits_invits: 51_000, # +0.1pp
          infrastructure_funds: 69_000, # -0.1pp
          cash_liquid_funds: 49_000, # -0.1pp
          gold_silver_etfs: 26_000 # -0.4pp
        }
      )
    end

    it "does not trigger (equity 55.5% stays inside the 50–60 band)" do
      expect(report).not_to be_rebalance_required
    end
  end
end
