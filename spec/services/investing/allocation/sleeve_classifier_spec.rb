# frozen_string_literal: true

require "rails_helper"

RSpec.describe Investing::Allocation::SleeveClassifier do
  subject(:sleeve_key) { described_class.call(instrument, policy: policy) }

  let(:policy) { create(:investment_policy, :balanced) }

  # The instruments table gains asset_class/sector in the classification
  # migration (TDD §4.1), which ships after the spike — so verified
  # instance_doubles cannot see those readers yet. A Struct stands in for
  # the instrument interface SleeveClassifier consumes.
  let(:instrument_struct) do
    Struct.new(:asset_class, :display_name, :symbol_name, :custom_symbol,
               keyword_init: true)
  end

  def build_instrument(asset_class:, display_name: nil, symbol_name: nil, custom_symbol: nil)
    instrument_struct.new(asset_class: asset_class, display_name: display_name,
                          symbol_name: symbol_name, custom_symbol: custom_symbol)
  end

  context "with plain equity" do
    let(:instrument) do
      build_instrument(asset_class: "equity", display_name: "HDFC BANK",
                       symbol_name: "HDFCBANK")
    end

    it { is_expected.to eq("indian_large_cap") }
  end

  context "with ETFs (keyword routing)" do
    it "routes a mid-cap ETF" do
      etf = build_instrument(asset_class: "etf", display_name: "NIFTY MIDCAP 150",
                             symbol_name: "MID150BEES")
      expect(described_class.call(etf, policy: policy)).to eq("indian_mid_small_cap")
    end

    it "routes a gold ETF" do
      etf = build_instrument(asset_class: "etf", symbol_name: "GOLDBEES")
      expect(described_class.call(etf, policy: policy)).to eq("gold_silver_etfs")
    end

    it "routes an infrastructure ETF" do
      etf = build_instrument(asset_class: "etf", display_name: "INFRA BEES")
      expect(described_class.call(etf, policy: policy)).to eq("infrastructure_funds")
    end

    it "routes an international ETF" do
      etf = build_instrument(asset_class: "etf", symbol_name: "NASDAQ100ETF")
      expect(described_class.call(etf, policy: policy)).to eq("global_equity")
    end

    it "routes a technology ETF" do
      etf = build_instrument(asset_class: "etf", symbol_name: "TECHBEES")
      expect(described_class.call(etf, policy: policy)).to eq("technology_clean_energy")
    end

    it "routes a liquid ETF" do
      etf = build_instrument(asset_class: "etf", symbol_name: "LIQUIDBEES")
      expect(described_class.call(etf, policy: policy)).to eq("cash_liquid_funds")
    end

    it "defaults a generic index ETF to large cap" do
      etf = build_instrument(asset_class: "etf", symbol_name: "NIFTYBEES")
      expect(described_class.call(etf, policy: policy)).to eq("indian_large_cap")
    end
  end

  context "with other asset classes" do
    it "routes REITs/InvITs" do
      expect(described_class.call(
        build_instrument(asset_class: "reit_invit", symbol_name: "EMBASSY"), policy: policy
      )).to eq("reits_invits")
    end

    it "routes government bonds" do
      expect(described_class.call(
        build_instrument(asset_class: "government_bond", symbol_name: "728GS2033"), policy: policy
      )).to eq("government_aaa_bonds")
    end

    it "routes corporate bonds to short-duration debt" do
      expect(described_class.call(
        build_instrument(asset_class: "corporate_bond", symbol_name: "BBCP"), policy: policy
      )).to eq("short_duration_debt")
    end
  end

  context "when the asset class is missing" do
    let(:instrument) { build_instrument(asset_class: nil, symbol_name: "UNKNOWN") }

    it { is_expected.to be_nil }
  end

  context "when the classified sleeve is not in the policy" do
    let(:narrow_policy) { create(:investment_policy, :active) }

    it "stays unclassified instead of guessing" do
      etf = build_instrument(asset_class: "etf", symbol_name: "GOLDBEES")
      result = described_class.call(etf, policy: narrow_policy)

      expect(result).to be_nil
    end
  end

  context "with an explicit symbol override in the policy" do
    let(:override_policy) do
      policy = create(:investment_policy, :active)
      create(:investment_policy_sleeve, investment_policy: policy,
                                        sleeve_key: "global_equity",
                                        group_key: "equity",
                                        target_pct: 10,
                                        instrument_filter: { "symbols" => ["MOTHERDEWL"] })
      policy
    end

    it "honors the filter over the static map" do
      stock = build_instrument(asset_class: "equity", symbol_name: "MOTHERDEWL")
      result = described_class.call(stock, policy: override_policy)

      expect(result).to eq("global_equity")
    end
  end
end
