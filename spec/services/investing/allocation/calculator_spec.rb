# frozen_string_literal: true

require "rails_helper"

RSpec.describe Investing::Allocation::Calculator do
  subject(:calculator) { described_class.new }

  # FY2026-27 illustrative default — must mirror config/investing.yml exactly
  # (TDD §17 skeleton; verified against Investing::Config in config_spec).
  let(:sleeves) do
    [
      { sleeve_key: "large_cap_core",      asset_class: "equity", target_weight_pct: 25 },
      { sleeve_key: "mid_small_cap",       asset_class: "equity", target_weight_pct: 10 },
      { sleeve_key: "global_equity",       asset_class: "equity", target_weight_pct: 10 },
      { sleeve_key: "thematic_tech_clean", asset_class: "equity", target_weight_pct: 10 },
      { sleeve_key: "govt_aaa_bonds",      asset_class: "debt",   target_weight_pct: 15 },
      { sleeve_key: "short_duration_debt", asset_class: "debt",   target_weight_pct: 10 },
      { sleeve_key: "reit_invit",          asset_class: "reit",   target_weight_pct: 5 },
      { sleeve_key: "infra",               asset_class: "infra",  target_weight_pct: 7 },
      { sleeve_key: "cash",                asset_class: "cash",   target_weight_pct: 5 },
      { sleeve_key: "gold_silver",         asset_class: "gold",   target_weight_pct: 3 }
    ].map { |s| Struct.new(*s.keys).new(**s) }
  end

  def valuation_with(holding_values: {}, cash: 0)
    values = holding_values.transform_values { |v| BigDecimal(v.to_s) }
    cash_d = BigDecimal(cash.to_s)
    Struct.new(:total_value, :cash_value, :sleeve_values).new(
      values.values.sum + cash_d, cash_d, values
    )
  end

  # Fully invested at exactly target (hand-clean fixture)
  def at_target_valuation
    valuation_with(
      holding_values: {
        "large_cap_core" => 25_000, "mid_small_cap" => 10_000, "global_equity" => 10_000,
        "thematic_tech_clean" => 10_000, "govt_aaa_bonds" => 15_000,
        "short_duration_debt" => 10_000, "reit_invit" => 5_000, "infra" => 7_000,
        "gold_silver" => 3_000
      },
      cash: 5_000
    )
  end

  describe "#report" do
    it "sums actual weights to exactly 100.00 for a fully invested portfolio" do
      report = calculator.report(sleeves, at_target_valuation)
      expect(report.rows.sum(&:actual_pct)).to eq(100)
    end

    it "computes target/actual/drift hand-verified values at target" do
      report = calculator.report(sleeves, at_target_valuation)
      row = report.row("large_cap_core")
      expect(row.target_pct).to eq(25)
      expect(row.actual_pct).to eq(25)
      expect(row.drift_pct).to eq(0)
      expect(row.target_value).to eq(25_000)
      expect(row.actual_value).to eq(25_000)
      expect(row.delta_value).to eq(0)
    end

    it "treats uninvested cash as cash-sleeve overweight (no spreading)" do
      report = calculator.report(sleeves, valuation_with(holding_values: { "large_cap_core" => 40_000 }, cash: 60_000))
      expect(report.row("cash").actual_pct).to eq(60)
      expect(report.row("large_cap_core").actual_pct).to eq(40)
    end

    it "computes hand-verified drift for the canonical fixture" do
      # total 100_000; large_cap 30_000 vs target 25_000 ⇒ +5.0pp drift (TDD §17)
      report = calculator.report(sleeves, valuation_with(holding_values: { "large_cap_core" => 30_000 }, cash: 70_000))
      expect(report.row("large_cap_core").drift_pct).to eq(5)
      expect(report.row("large_cap_core").delta_value).to eq(5_000)
    end

    describe "equity band boundaries (TDD §7.1 rule 6 — 2dp half-up, inclusive)" do
      it "is inside the band at exactly 60.00" do
        values = { "large_cap_core" => 30_000, "mid_small_cap" => 12_000,
                   "global_equity" => 9_000, "thematic_tech_clean" => 9_000 }
        report = calculator.report(sleeves, valuation_with(holding_values: values, cash: 40_000))
        expect(report.equity_weight_pct).to eq(60)
        expect(report).to be_within_equity_band
      end

      it "is outside the band at 60.01" do
        values = { "large_cap_core" => 30_000, "mid_small_cap" => 12_000,
                   "global_equity" => 9_010, "thematic_tech_clean" => 9_000 }
        report = calculator.report(sleeves, valuation_with(holding_values: values, cash: 39_990))
        expect(report.equity_weight_pct).to eq(60.01)
        expect(report).not_to be_within_equity_band
      end

      it "is inside the band at 59.99" do
        values = { "large_cap_core" => 30_000, "mid_small_cap" => 12_000,
                   "global_equity" => 9_010, "thematic_tech_clean" => 8_990 }
        # equity = 59_990 → 59.99%
        report = calculator.report(sleeves, valuation_with(holding_values: values, cash: 40_010))
        expect(report.equity_weight_pct).to eq(59.99)
        expect(report).to be_within_equity_band
      end

      it "is inside the band at exactly 50.00" do
        values = { "large_cap_core" => 25_000, "mid_small_cap" => 10_000,
                   "global_equity" => 10_000, "thematic_tech_clean" => 5_000 }
        report = calculator.report(sleeves, valuation_with(holding_values: values, cash: 50_000))
        expect(report.equity_weight_pct).to eq(50)
        expect(report).to be_within_equity_band
      end

      it "is outside the band at 49.99" do
        values = { "large_cap_core" => 25_000, "mid_small_cap" => 10_000,
                   "global_equity" => 10_000, "thematic_tech_clean" => 4_990 }
        report = calculator.report(sleeves, valuation_with(holding_values: values, cash: 50_010))
        expect(report.equity_weight_pct).to eq(49.99)
        expect(report).not_to be_within_equity_band
      end
    end

    it "reports a sleeve with no holdings at -target drift" do
      report = calculator.report(sleeves, valuation_with(cash: 100_000))
      gold = report.row("gold_silver")
      expect(gold.actual_pct).to eq(0)
      expect(gold.actual_value).to eq(0)
      expect(gold.drift_pct).to eq(-3)
    end

    it "flags breached sleeves at/over the drift threshold" do
      report = calculator.report(
        sleeves,
        valuation_with(holding_values: { "large_cap_core" => 30_000 }, cash: 70_000),
        drift_threshold: 5
      )
      expect(report.breached_sleeves.map(&:sleeve_key)).to contain_exactly(
        "large_cap_core", "cash", "mid_small_cap", "global_equity",
        "thematic_tech_clean", "govt_aaa_bonds", "short_duration_debt",
        "reit_invit", "infra"
      )
      # gold_silver drift is -3pp — below the 5pp threshold, NOT breached
    end

    it "does not breach when drift is below the threshold" do
      report = calculator.report(
        sleeves,
        valuation_with(holding_values: { "large_cap_core" => 25_500 }, cash: 74_500),
        drift_threshold: 5
      )
      expect(report.breached_sleeves.map(&:sleeve_key)).not_to include("large_cap_core")
    end

    it "returns all-zero actuals for a zero-value portfolio (no div-by-zero)" do
      report = calculator.report(sleeves, valuation_with(cash: 0))
      expect(report.rows.map(&:actual_pct)).to all(eq(0))
      expect(report.equity_weight_pct).to eq(0)
      expect(report).not_to be_within_equity_band
    end

    it "accepts AR AllocationSleeve rows (duck-typing)" do
      policy = InvestmentPolicy.new(status: "draft", mandate_version: "balanced_v1",
                                    rebalance_band_min_pct: 50, rebalance_band_max_pct: 60)
      sleeves.each_with_index do |s, i|
        policy.allocation_sleeves.build(
          sleeve_key: s.sleeve_key, sleeve_name: s.sleeve_key, asset_class: s.asset_class,
          target_weight_pct: s.target_weight_pct, display_order: i
        )
      end
      report = calculator.report(policy.allocation_sleeves, at_target_valuation)
      expect(report.row("large_cap_core").actual_pct).to eq(25)
    end

    it "is serializable via to_h for drift_report storage" do
      report = calculator.report(sleeves, valuation_with(holding_values: { "large_cap_core" => 30_000 }, cash: 70_000))
      h = report.to_h
      expect(h[:equity_weight_pct]).to eq("30.0")
      expect(h[:within_equity_band]).to be(false)
      expect(h[:rows].find { |r| r[:sleeve_key] == "large_cap_core" }[:drift_pct]).to eq("5.0")
    end
  end
end
