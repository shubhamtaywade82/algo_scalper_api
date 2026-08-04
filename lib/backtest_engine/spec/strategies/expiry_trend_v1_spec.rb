# frozen_string_literal: true

require "spec_helper"

RSpec.describe BacktestEngine::Strategies::ExpiryTrendV1 do
  def context_for(overrides = {})
    {
      structure: :bullish,
      pullback: true,
      volume_ratio: 2.0,
      regime_score: 75.0,
      iv_expansion: 5.0,
      htf_bias: :bullish,
      iv: nil
    }.merge(overrides)
  end

  def strategy(overrides = {})
    described_class.new(context: context_for(overrides))
  end

  describe "#call" do
    context "regime gate" do
      it "skips when regime_score is nil (graceful nil-safety)" do
        result = strategy(regime_score: nil, iv_expansion: nil).call
        expect(result[:action]).to eq(:skip)
        expect(result[:reason]).to match(/Weak regime/)
      end

      it "skips when regime_strength is below STRENGTH_FLOOR" do
        # score=53 → effective=53, strength=|53-50|=3 < STRENGTH_FLOOR=5
        result = strategy(regime_score: 53.0, iv_expansion: 0.0, htf_bias: nil).call
        expect(result[:action]).to eq(:skip)
        expect(result[:reason]).to match(/Weak regime/)
      end

      it "trades when regime_strength meets STRENGTH_FLOOR exactly" do
        # score=55 → effective=55, strength=|55-50|=5 ≥ STRENGTH_FLOOR=5
        result = strategy(regime_score: 55.0, iv_expansion: 0.0, htf_bias: nil).call
        expect(result[:action]).to eq(:buy)
      end

      it "applies htf_bias misalignment as -5 penalty" do
        # score=58, htf_misaligned=-5 → effective=53, strength=|53-50|=3 < STRENGTH_FLOOR=5 → skip
        result = strategy(regime_score: 58.0, iv_expansion: 0.0, htf_bias: :bearish, structure: :bullish).call
        expect(result[:action]).to eq(:skip)
        expect(result[:reason]).to match(/Weak regime/)
      end

      it "does not penalise when htf_bias is nil" do
        result = strategy(regime_score: 60.0, iv_expansion: 0.0, htf_bias: nil).call
        expect(result[:action]).to eq(:buy)
      end
    end

    context "structure gate" do
      it "skips when structure is :range" do
        result = strategy(structure: :range).call
        expect(result[:action]).to eq(:skip)
        expect(result[:reason]).to match(/No structure/)
      end
    end

    context "pullback gate" do
      it "skips when pullback is false" do
        result = strategy(pullback: false).call
        expect(result[:action]).to eq(:skip)
        expect(result[:reason]).to match(/No pullback/)
      end
    end

    context "volume gate (adaptive threshold)" do
      it "skips when volume_ratio is below threshold for the score band" do
        # score=60 → strength=|60-50|=10 → factor=1.4; ratio=1.3 < 1.4 → skip
        result = strategy(regime_score: 60.0, iv_expansion: 0.0, htf_bias: nil, volume_ratio: 1.3).call
        expect(result[:action]).to eq(:skip)
        expect(result[:reason]).to match(/No setup/)
      end

      it "trades when volume_ratio meets threshold for the score band" do
        # score=60 → strength=|60-50|=10 → factor=1.4; ratio=1.4 >= 1.4 → trade
        result = strategy(regime_score: 60.0, iv_expansion: 0.0, htf_bias: nil, volume_ratio: 1.4).call
        expect(result[:action]).to eq(:buy)
      end

      it "uses a lower threshold at high scores" do
        # score=80 → strength=|80-50|=30 → factor=1.05; ratio=1.1 >= 1.05 → trade
        result = strategy(regime_score: 80.0, iv_expansion: 0.0, htf_bias: nil, volume_ratio: 1.1).call
        expect(result[:action]).to eq(:buy)
      end

      it "skips when volume_ratio is below threshold for the floor score band" do
        # score=55 → strength=|55-50|=5 → factor=1.8; ratio=1.7 < 1.8 → skip
        result = strategy(regime_score: 55.0, iv_expansion: 0.0, htf_bias: nil, volume_ratio: 1.7).call
        expect(result[:action]).to eq(:skip)
        expect(result[:reason]).to match(/No setup/)
      end

      it "trades when volume_ratio meets threshold for the floor score band" do
        # score=55 → strength=|55-50|=5 → factor=1.8; ratio=1.8 >= 1.8 → trade
        result = strategy(regime_score: 55.0, iv_expansion: 0.0, htf_bias: nil, volume_ratio: 1.8).call
        expect(result[:action]).to eq(:buy)
      end

      it "applies the same adaptive threshold for bearish structure" do
        # score=60 → strength=|60-50|=10 → factor=1.4; bearish structure with ratio=1.3 → skip
        result = strategy(structure: :bearish, htf_bias: :bearish, regime_score: 60.0, iv_expansion: 0.0, volume_ratio: 1.3).call
        expect(result[:action]).to eq(:skip)
        expect(result[:reason]).to match(/No setup/)
      end
    end

    context "direction" do
      it "generates buy call for bullish structure" do
        result = strategy(structure: :bullish).call
        expect(result[:action]).to eq(:buy)
        expect(result[:option_type]).to eq(:call)
      end

      it "generates buy put for bearish structure" do
        result = strategy(structure: :bearish, htf_bias: :bearish).call
        expect(result[:action]).to eq(:buy)
        expect(result[:option_type]).to eq(:put)
      end
    end

    context "no time window" do
      it "does not skip based on time of day (ENTRY_WINDOW removed)" do
        # strategy.call uses context_for defaults — no time field — confirms no time check exists
        result = strategy.call
        expect(result[:action]).to eq(:buy)
      end
    end

    context "bearish regime" do
      it "trades bearish structure when bearish regime strength is sufficient" do
        # score=42 → effective=42, strength=|42-50|=8 ≥ 5; factor=1.8 (8 < 10); volume_ratio=2.0 ≥ 1.8 → buy put
        result = strategy(regime_score: 42.0, iv_expansion: 0.0, htf_bias: :bearish, structure: :bearish).call
        expect(result[:action]).to eq(:buy)
        expect(result[:option_type]).to eq(:put)
      end

      it "skips bearish entry when score is too close to neutral" do
        # score=47 → effective=47, strength=|47-50|=3 < STRENGTH_FLOOR=5 → skip
        result = strategy(regime_score: 47.0, iv_expansion: 0.0, htf_bias: :bearish, structure: :bearish).call
        expect(result[:action]).to eq(:skip)
        expect(result[:reason]).to match(/Weak regime/)
      end
    end
  end
end
