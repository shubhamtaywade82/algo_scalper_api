# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Trading::StrategyProfileSelector do
  before do
    allow(AlgoConfig).to receive(:fetch).and_return(
      market_context: {
        strategy_profiles: {
          aggressive_min_score: 80,
          controlled_min_score: 60
        }
      }
    )
  end

  describe '.select' do
    it 'returns trend_aggressive for strong bullish trend and high conviction' do
      snap = MarketContext::RegimeSnapshot.new(
        structure: :bullish_trend,
        strength: :strong,
        volatility_state: :normal,
        participation: :high,
        conviction_score: 85,
        displacement: true,
        legacy_regime: 'TRENDING_UP',
        legacy_confidence: 80.0,
        raw: {}
      )

      expect(described_class.select(snap)).to eq(:trend_aggressive)
    end

    it 'returns range_stand_down for chop' do
      snap = MarketContext::RegimeSnapshot.new(
        structure: :chop,
        strength: :weak,
        volatility_state: :normal,
        participation: :low,
        conviction_score: 30,
        displacement: false,
        legacy_regime: 'CHOPPY',
        legacy_confidence: 40.0,
        raw: {}
      )

      expect(described_class.select(snap)).to eq(:range_stand_down)
    end
  end
end
