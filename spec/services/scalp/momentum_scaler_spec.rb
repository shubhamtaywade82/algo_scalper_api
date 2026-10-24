# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Scalp::MomentumScaler do
  let(:cfg) { {} }

  def state(trend_score:, atr_ratio:, atr_trend: :flat, mtf_confirm: false, bos_state: :intact, bos_direction: :neutral)
    OpenStruct.new(
      trend_score: trend_score, atr_ratio: atr_ratio, atr_trend: atr_trend,
      mtf_confirm: mtf_confirm, bos_state: bos_state, bos_direction: bos_direction,
      ltp: nil, smc_bias_flip: false
    )
  end

  before do
    allow(AlgoConfig).to receive(:fetch).and_return({
      risk: {
        underlying_context_exit: {
          atr_ratio_threshold: 0.65,
          momentum_scaling: { enabled: true }
        }
      }
    })
  end

  describe '.enabled?' do
    it 'is opt-in: absent section is disabled' do
      allow(AlgoConfig).to receive(:fetch).and_return({ risk: { underlying_context_exit: {} } })
      expect(described_class.enabled?).to be false
    end

    it 'is disabled when the section is not a hash' do
      allow(AlgoConfig).to receive(:fetch).and_return(
        { risk: { underlying_context_exit: { momentum_scaling: true } } }
      )
      expect(described_class.enabled?).to be false
    end

    it 'is enabled only when explicitly true' do
      expect(described_class.enabled?).to be true
    end
  end

  describe '#score' do
    it 'returns nil when the core trend signal is unavailable (no fabrication)' do
      expect(described_class.new.score(state(trend_score: nil, atr_ratio: 0.9), :bullish)).to be_nil
      expect(described_class.new.score(nil, :bullish)).to be_nil
    end

    it 'scales the trend component by trend_score_max and clamps at 1.0' do
      scaler = described_class.new
      low = scaler.score(state(trend_score: 22.5, atr_ratio: 1.1, mtf_confirm: true, bos_state: :intact), :bullish)
      high = scaler.score(
        state(trend_score: 90.0, atr_ratio: 1.1, mtf_confirm: true, bos_state: :broken, bos_direction: :bullish),
        :bullish
      )
      # trend 22.5/45 = 0.5 vs 90/45 -> clamped 1.0; perfect rest -> exactly 1.0
      expect(high).to be > low
      expect(high).to eq(1.0)
    end

    it 'maps atr_ratio below the collapse threshold to zero contribution' do
      scaler = described_class.new
      collapsed = scaler.score(state(trend_score: 45.0, atr_ratio: 0.50, mtf_confirm: true), :bullish)
      healthy = scaler.score(state(trend_score: 45.0, atr_ratio: 1.10, mtf_confirm: true), :bullish)
      expect(healthy).to be > collapsed
    end

    it 'treats unknown atr_ratio as neutral 0.5, not as collapse' do
      scaler = described_class.new
      unknown = scaler.score(state(trend_score: 45.0, atr_ratio: nil, mtf_confirm: true), :bullish)
      collapsed = scaler.score(state(trend_score: 45.0, atr_ratio: 0.50, mtf_confirm: true), :bullish)
      expect(unknown).to be > collapsed
    end

    it 'rewards BOS displacement in the position direction over an intact structure' do
      scaler = described_class.new
      base = state(trend_score: 45.0, atr_ratio: 1.0, mtf_confirm: true, bos_state: :intact, bos_direction: :neutral)
      in_favour = state(trend_score: 45.0, atr_ratio: 1.0, mtf_confirm: true, bos_state: :broken, bos_direction: :bullish)
      against = state(trend_score: 45.0, atr_ratio: 1.0, mtf_confirm: true, bos_state: :broken, bos_direction: :bearish)

      expect(scaler.score(in_favour, :bullish)).to be > scaler.score(base, :bullish)
      expect(scaler.score(against, :bullish)).to be < scaler.score(base, :bullish)
      expect(scaler.score(against, :bearish)).to be > scaler.score(against, :bullish)
    end
  end

  describe '#death?' do
    it 'fires below the death threshold and not above it' do
      scaler = described_class.new
      expect(scaler.death?(0.29)).to be true
      expect(scaler.death?(0.30)).to be false
    end

    it 'never fires on an unknown score' do
      expect(described_class.new.death?(nil)).to be false
    end

    it 'honours a configured threshold' do
      scaler = described_class.new(death_threshold: 0.5)
      expect(scaler.death?(0.45)).to be true
      expect(scaler.death?(0.55)).to be false
    end
  end

  describe '#multiplier' do
    it 'returns exactly 1.0 for an unknown score' do
      expect(described_class.new.multiplier(nil)).to eq(1.0)
    end

    it 'interpolates linearly between min and max multiplier' do
      scaler = described_class.new(min_multiplier: 0.6, max_multiplier: 1.4)
      expect(scaler.multiplier(0.0)).to eq(0.6)
      expect(scaler.multiplier(0.5)).to eq(1.0)
      expect(scaler.multiplier(1.0)).to eq(1.4)
    end

    it 'clamps scores outside [0, 1]' do
      scaler = described_class.new(min_multiplier: 0.6, max_multiplier: 1.4)
      expect(scaler.multiplier(5.0)).to eq(1.4)
      expect(scaler.multiplier(-3.0)).to eq(0.6)
    end
  end

  describe 'strict config reads' do
    it 'raises ConfigurationError on garbage values' do
      scaler = described_class.new(trend_score_max: 'very')
      expect { scaler.score(state(trend_score: 30.0, atr_ratio: 0.9), :bullish) }
        .to raise_error(Errors::ConfigurationError, /trend_score_max/)
    end

    it 'reads the shared ATR threshold from the evaluator config' do
      allow(AlgoConfig).to receive(:fetch).and_return({
        risk: { underlying_context_exit: { atr_ratio_threshold: 'not-a-number' } }
      })
      scaler = described_class.new
      expect { scaler.score(state(trend_score: 30.0, atr_ratio: 0.9), :bullish) }
        .to raise_error(Errors::ConfigurationError, /atr_ratio_threshold/)
    end
  end
end
