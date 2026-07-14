# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Trading::MarketPermissionGate do
  let(:snapshot) do
    MarketContext::RegimeSnapshot.new(
      structure: :bullish_trend,
      strength: :strong,
      volatility_state: :normal,
      participation: :high,
      conviction_score: 85,
      displacement: true,
      legacy_regime: 'TRENDING_UP',
      legacy_confidence: 70.0,
      raw: {}
    )
  end

  let(:chain_result) do
    Struct.new(
      :direction_confidence, :direction_hint, :oi_confirmation,
      :premium_expansion, :pcr, :near_expiry_penalty, keyword_init: true
    )
  end

  let(:chain) do
    chain_result.new(
      direction_confidence: 55,
      direction_hint: :bullish,
      oi_confirmation: true,
      premium_expansion: false,
      pcr: 1.1,
      near_expiry_penalty: false
    )
  end

  before do
    allow(AlgoConfig).to receive(:fetch).and_return(
      market_context: {
        gate: {
          enabled: true,
          min_conviction_score: 70,
          min_chain_confidence: 40,
          allow_normal_participation: true,
          require_premium_expansion: false
        }
      }
    )
  end

  describe '#call' do
    it 'allows when all checks pass' do
      result = described_class.new(
        snapshot: snapshot,
        chain_signal: chain,
        final_direction: :bullish
      ).call

      expect(result.allowed).to be true
    end

    it 'rejects when conviction is below minimum' do
      low = MarketContext::RegimeSnapshot.new(
        structure: :bullish_trend,
        strength: :strong,
        volatility_state: :normal,
        participation: :high,
        conviction_score: 40,
        displacement: true,
        legacy_regime: 'TRENDING_UP',
        legacy_confidence: 40.0,
        raw: {}
      )

      result = described_class.new(snapshot: low, chain_signal: chain, final_direction: :bullish).call

      expect(result.allowed).to be false
      expect(result.code).to eq(:low_conviction)
    end

    it 'rejects when structure is not directional' do
      range_snap = MarketContext::RegimeSnapshot.new(
        structure: :range,
        strength: :strong,
        volatility_state: :normal,
        participation: :high,
        conviction_score: 90,
        displacement: false,
        legacy_regime: 'RANGING',
        legacy_confidence: 50.0,
        raw: {}
      )

      result = described_class.new(snapshot: range_snap, chain_signal: chain, final_direction: :bullish).call

      expect(result.allowed).to be false
      expect(result.code).to eq(:not_trending)
    end
  end
end
