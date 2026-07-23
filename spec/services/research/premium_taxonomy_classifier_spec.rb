# frozen_string_literal: true

require "rails_helper"

RSpec.describe Research::PremiumTaxonomyClassifier do
  describe ".classify" do
    let(:base_time) { Time.zone.parse("2026-07-14 09:15:00") }

    def build_candles(prices)
      prices.each_with_index.map do |p, i|
        {
          timestamp: base_time + i.minutes,
          open: p.to_f,
          high: (p * 1.02).round(2),
          low: (p * 0.98).round(2),
          close: p.to_f,
          volume: 1000
        }
      end
    end

    it "returns :neutral for empty/invalid data" do
      expect(described_class.classify([], 0.0, 0.0)).to eq(:neutral)
      expect(described_class.classify(build_candles([0, 0]), 0.0, 0.0)).to eq(:neutral)
    end

    it "classifies :straight_expansion when MFE is high, peak is late, and drawdown is low" do
      # Premium rises from 100 to 200 at minute 12, closes at 200. MFE is 100%. No post-peak drawdown.
      prices = [100, 110, 120, 130, 140, 150, 160, 170, 180, 185, 190, 195, 200]
      candles = build_candles(prices)
      # Override highs/lows for exact matching
      candles.each { |c| c[:high] = c[:close]; c[:low] = c[:close] }
      candles[12][:high] = 200.0

      result = described_class.classify(candles, 100.0, 0.0)
      expect(result).to eq(:straight_expansion)
    end

    it "classifies :spike_and_decay when peak is early followed by heavy decay" do
      # Premium rises from 100 to 180 at minute 3 (peak), then collapses to 70 at the end
      prices = [100, 140, 160, 180, 150, 130, 110, 100, 90, 80, 75, 70, 70]
      candles = build_candles(prices)
      candles.each { |c| c[:high] = c[:close]; c[:low] = c[:close] }
      candles[3][:high] = 180.0

      result = described_class.classify(candles, 80.0, -30.0)
      expect(result).to eq(:spike_and_decay)
    end

    it "classifies :post_open_collapse when entry/minute 0 is peak and close drops heavily" do
      # Entry is 150. Drops continuously to 80.
      prices = [150, 140, 130, 120, 110, 105, 100, 95, 90, 85, 80, 80, 80]
      candles = build_candles(prices)
      candles.each { |c| c[:high] = c[:close]; c[:low] = c[:close] }
      # Make minute 0 the peak
      candles[0][:high] = 150.0

      result = described_class.classify(candles, 0.0, -46.7)
      expect(result).to eq(:post_open_collapse)
    end

    it "classifies :compression when premium stays range-bound" do
      # Premium oscillates between 95 and 105
      prices = [100, 102, 98, 101, 99, 103, 100, 97, 102, 100, 101, 99, 100]
      candles = build_candles(prices)
      candles.each { |c| c[:high] = c[:close]; c[:low] = c[:close] }

      result = described_class.classify(candles, 5.0, -5.0)
      expect(result).to eq(:compression)
    end

    it "classifies :whipsaw when there are large moves in both directions" do
      # Premium spikes from 100 to 140 (MFE 40%), but drops to 70 (MAE -30%)
      prices = [100, 120, 140, 110, 80, 70, 90, 110, 120, 115, 110, 105, 100]
      candles = build_candles(prices)
      candles.each { |c| c[:high] = c[:close]; c[:low] = c[:close] }
      candles[2][:high] = 140.0
      candles[5][:low] = 70.0

      result = described_class.classify(candles, 40.0, -30.0)
      expect(result).to eq(:whipsaw)
    end
  end
end
