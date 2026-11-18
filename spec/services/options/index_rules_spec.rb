# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Options::IndexRules do
  describe '.for' do
    it 'returns the rules for each supported index' do
      expect(described_class.for('NIFTY')).to be_a(described_class::Nifty)
      expect(described_class.for('BANKNIFTY')).to be_a(described_class::Banknifty)
      expect(described_class.for('SENSEX')).to be_a(described_class::Sensex)
    end

    it 'accepts symbols, lowercase and padded keys' do
      expect(described_class.for(:banknifty)).to be_a(described_class::Banknifty)
      expect(described_class.for('  sensex ')).to be_a(described_class::Sensex)
    end

    it 'returns nil for an unknown index so each caller keeps its own policy for that case' do
      expect(described_class.for('FINNIFTY')).to be_nil
      expect(described_class.for(nil)).to be_nil
    end
  end

  # One contract for every index: the three classes differ only in their numbers.
  shared_examples 'an index rule set' do |index:, step:, min_volume:, min_premium:, max_spread_pct:|
    subject(:rules) { described_class.for(index) }

    it 'has its own strike step' do
      expect(rules.strike_step).to eq(step)
    end

    it 'rounds spot to the nearest strike step' do
      expect(rules.atm((step * 10) + (step / 2.0) - 1)).to eq(step * 10)
      expect(rules.atm((step * 10) + (step / 2.0))).to eq((step * 10) + step)
    end

    it 'takes its lot size from the instrument master' do
      allow(Trading::LotCalculator).to receive(:lot_size_for).with(index).and_return(99)
      expect(rules.lot_size).to eq(99)
    end

    it 'maps direction to option type' do
      expect(rules.option_type(:bullish)).to eq('CE')
      expect(rules.option_type(:bearish)).to eq('PE')
    end

    it 'applies its own liquidity floor' do
      expect(rules.valid_liquidity?(volume: min_volume)).to be true
      expect(rules.valid_liquidity?(volume: min_volume - 1)).to be false
      expect(rules.valid_liquidity?('volume' => min_volume)).to be true
    end

    it 'applies its own premium floor' do
      expect(rules.valid_premium?(ltp: min_premium)).to be true
      expect(rules.valid_premium?(ltp: min_premium - 0.01)).to be false
      expect(rules.valid_premium?('ltp' => min_premium)).to be true
    end

    it 'applies its own bid/ask spread ceiling' do
      ask = 200.0
      inside = ask * (1 - (max_spread_pct * 0.99))
      outside = ask * (1 - (max_spread_pct * 1.5))

      expect(rules.valid_spread?(bid: inside, ask: ask)).to be true
      expect(rules.valid_spread?(bid: outside, ask: ask)).to be false
      expect(rules.valid_spread?(bid: 0, ask: ask)).to be false
    end

    it 'has a multiplier of 1' do
      expect(rules.multiplier).to eq(1)
    end
  end

  describe 'NIFTY' do
    it_behaves_like 'an index rule set', index: 'NIFTY', step: 50, min_volume: 30_000, min_premium: 25.0, max_spread_pct: 0.003

    it 'also considers the next strike up' do
      expect(described_class.for('NIFTY').candidate_strikes(25_100)).to eq([25_100, 25_150])
    end

    it 'falls back to last_price when ltp is absent' do
      expect(described_class.for('NIFTY').valid_premium?(last_price: 30.0)).to be true
    end
  end

  describe 'BANKNIFTY' do
    it_behaves_like 'an index rule set', index: 'BANKNIFTY', step: 100, min_volume: 50_000, min_premium: 40.0, max_spread_pct: 0.005

    it 'considers only the ATM strike and does not read last_price' do
      rules = described_class.for('BANKNIFTY')

      expect(rules.candidate_strikes(62_300)).to eq([62_300])
      expect(rules.valid_premium?(last_price: 90.0)).to be false
    end
  end

  describe 'SENSEX' do
    it_behaves_like 'an index rule set', index: 'SENSEX', step: 100, min_volume: 20_000, min_premium: 30.0, max_spread_pct: 0.003

    it 'considers only the ATM strike and does not read last_price' do
      rules = described_class.for('SENSEX')

      expect(rules.candidate_strikes(82_800)).to eq([82_800])
      expect(rules.valid_premium?(last_price: 90.0)).to be false
    end
  end

  # Values the expected-move check used to keep in its own per-index case statements.
  describe 'expected-move parameters' do
    {
      'NIFTY' => { atm: 0.48, other: 0.40, thresholds: { execution_only: 4.0, scale_ready: 8.0, full_deploy: 12.0 } },
      'BANKNIFTY' => { atm: 0.45, other: 0.38, thresholds: { execution_only: 12.0, scale_ready: 20.0, full_deploy: 28.0 } },
      'SENSEX' => { atm: 0.50, other: 0.42, thresholds: { execution_only: nil, scale_ready: 15.0, full_deploy: 25.0 } }
    }.each do |index, expected|
      it "gives #{index} its delta buckets and move thresholds" do
        rules = described_class.for(index)

        expect(rules.delta_bucket(:ATM)).to eq(expected[:atm])
        expect(rules.delta_bucket(:ATM_PLUS_1)).to eq(expected[:other])
        expect(rules.delta_bucket(:ATM_MINUS_1)).to eq(expected[:other])
        expected[:thresholds].each { |permission, points| expect(rules.move_threshold_points(permission)).to eq(points) }
        expect(rules.move_threshold_points(:unknown)).to be_nil
      end
    end
  end
end
