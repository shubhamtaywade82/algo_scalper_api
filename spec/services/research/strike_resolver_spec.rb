# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Research::StrikeResolver do
  describe '.atm' do
    it 'rounds NIFTY to nearest 50' do
      expect(described_class.atm(symbol: 'NIFTY', spot: 24_982)).to eq(25_000)
    end

    it 'rounds BANKNIFTY/SENSEX to nearest 100' do
      expect(described_class.atm(symbol: 'BANKNIFTY', spot: 51_240)).to eq(51_200)
      expect(described_class.atm(symbol: 'SENSEX', spot: 81_260)).to eq(81_300)
    end
  end

  describe '.candidates' do
    it 'builds strikes from ATM-max_distance to ATM+max_distance' do
      candidates = described_class.candidates(symbol: 'NIFTY', spot: 24_982, option_type: 'CE', max_distance: 2)

      expect(candidates.pluck(:distance)).to eq([-2, -1, 0, 1, 2])
      expect(candidates.pluck(:actual_strike)).to eq([24_900, 24_950, 25_000, 25_050, 25_100])
      expect(candidates.pluck(:strike_label)).to eq(%w[ATM-2 ATM-1 ATM ATM+1 ATM+2])
    end
  end

  describe '.dhan_strike_param' do
    it 'returns ATM-relative format (DhanHQ API expects ATM/ATM+N/ATM-N)' do
      expect(described_class.dhan_strike_param(option_type: 'CE', distance: 0)).to eq('ATM')
      expect(described_class.dhan_strike_param(option_type: 'CE', distance: -1)).to eq('ATM-1')
      expect(described_class.dhan_strike_param(option_type: 'CE', distance: 2)).to eq('ATM+2')
      expect(described_class.dhan_strike_param(option_type: 'PE', distance: 1)).to eq('ATM+1')
      expect(described_class.dhan_strike_param(option_type: 'PE', distance: -2)).to eq('ATM-2')
    end
  end
end
