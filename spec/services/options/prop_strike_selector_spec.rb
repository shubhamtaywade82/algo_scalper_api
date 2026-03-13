# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Options::PropStrikeSelector do
  let(:spot) { 24200.0 }
  let(:selector) { described_class.new(spot: spot) }

  describe '#score' do
    let(:option) do
      {
        strike: 24200.0,
        delta: 0.5,
        oi: 500_000,
        volume: 50_000,
        spread: 0.005, # 0.5%
        ltp: 100.0
      }
    end

    it 'calculates a high score for ATM options with good delta and liquidity' do
      score = selector.score(option)
      expect(score).to be > 0.7 # High score for perfect candidate
    end

    it 'penalizes strikes far from spot' do
      far_option = option.merge(strike: 24500.0, delta: 0.2)
      expect(selector.score(far_option)).to be < selector.score(option)
    end

    it 'penalizes low liquidity' do
      illiquid_option = option.merge(oi: 1000, volume: 100, spread: 0.05)
      expect(selector.score(illiquid_option)).to be < selector.score(option)
    end

    it 'uses ratios when history is provided' do
      history = { avg_volume: 100_000, avg_oi: 1_000_000 }

      # Case 1: Volume spike (ratio 2.0)
      spike_option = option.merge(volume: 200_000, oi: 1_000_000)
      score_spike = selector.score(spike_option, history: history)

      # Case 2: Normal volume (ratio 1.0)
      normal_option = option.merge(volume: 100_000, oi: 1_000_000)
      score_normal = selector.score(normal_option, history: history)

      expect(score_spike).to be > score_normal
    end

    it 'boosts score with gamma pressure' do
      score_no_gamma = selector.score(option, gamma_pressure: 0.0)
      score_with_gamma = selector.score(option, gamma_pressure: 1.0)
      expect(score_with_gamma).to be > score_no_gamma
    end

    it 'boosts score with strong institutional flow' do
      score_normal_flow = selector.score(option, flow_score: 1.0)
      score_strong_flow = selector.score(option, flow_score: 2.0)
      expect(score_strong_flow).to be > score_normal_flow
    end
  end
end
