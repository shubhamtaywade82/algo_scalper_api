# frozen_string_literal: true

require 'rails_helper'

RSpec.describe OptionsBuying::ExpectedValueModel do
  describe '.ev' do
    it 'computes EV in risk units' do
      expect(described_class.ev(win_probability: 0.5, reward_multiple: 2.0)).to eq(0.5)
    end

    it 'returns zero when reward multiple is negative' do
      expect(described_class.ev(win_probability: 0.5, reward_multiple: -1.0)).to eq(0.0)
    end

    it 'clamps win probability to 0..1' do
      expect(described_class.ev(win_probability: 1.5, reward_multiple: 2.0)).to eq(2.0)
    end
  end

  describe '.break_even_win_rate' do
    it 'returns 1/(R+1)' do
      expect(described_class.break_even_win_rate(reward_multiple: 3.0)).to eq(0.25)
    end
  end

  describe '.reward_multiple' do
    it 'returns tp/sl ratio' do
      expect(described_class.reward_multiple(sl_pct: 0.15, tp_pct: 0.45)).to eq(3.0)
    end
  end

  describe '.grid' do
    it 'includes break-even and EV cells per reward row' do
      grid = described_class.grid(win_rates: [0.3], reward_multiples: [2.0])

      expect(grid[:win_rates]).to eq([0.3])
      expect(grid[:cells].first[:break_even_win_rate]).to eq(0.3333)
      expect(grid[:cells].first[:by_win_rate][0.3]).to eq(-0.1)
    end
  end
end
