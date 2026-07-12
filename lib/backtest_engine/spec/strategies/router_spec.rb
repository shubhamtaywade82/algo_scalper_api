# frozen_string_literal: true

require "spec_helper"

RSpec.describe BacktestEngine::Strategies::Router do
  describe "#tradable?" do
    it "returns true for trend_bull regime" do
      expect(described_class.new.tradable?(regime: :trend_bull)).to be true
    end

    it "returns true for trend_bear regime" do
      expect(described_class.new.tradable?(regime: :trend_bear)).to be true
    end

    it "returns false for chop regime" do
      expect(described_class.new.tradable?(regime: :chop)).to be false
    end

    it "returns false for nil regime" do
      expect(described_class.new.tradable?(regime: nil)).to be false
    end

    it "ignores extra keywords (backward compat splat)" do
      expect(described_class.new.tradable?(regime: :trend_bull, session: :s2, day_type: :normal)).to be true
    end
  end

  describe "#strategy_for" do
    it "returns ExpiryTrendV1 when regime is tradable" do
      expect(described_class.new.strategy_for(regime: :trend_bull)).to eq(BacktestEngine::Strategies::ExpiryTrendV1)
    end

    it "returns nil when regime is not tradable" do
      expect(described_class.new.strategy_for(regime: :chop)).to be_nil
    end
  end
end
