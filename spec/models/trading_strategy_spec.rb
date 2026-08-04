# frozen_string_literal: true

require "rails_helper"

RSpec.describe TradingStrategy do
  describe "#slugify" do
    it "parameterizes the name" do
      strategy = described_class.new(name: "Supertrend ADX v2!")
      expect(strategy.slugify).to eq("supertrend-adx-v2")
    end
  end

  describe "#deployed?" do
    it "is false without a strategy_record_id" do
      strategy = described_class.new(name: "X")
      expect(strategy.deployed?).to be false
    end

    it "is true once linked" do
      strategy = described_class.new(name: "X", strategy_record_id: 1)
      expect(strategy.deployed?).to be true
    end
  end

  describe "belongs_to :strategy_record" do
    it "is optional" do
      strategy = described_class.new(name: "X")
      expect(strategy).to be_valid
    end
  end
end
