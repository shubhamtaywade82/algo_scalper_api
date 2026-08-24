# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Options::Greeks::Calculator do
  describe '.estimate_delta' do
    context 'when IV and DTE are available' do
      it 'computes a real Black-Scholes delta rather than the legacy heuristic' do
        delta = described_class.estimate_delta(
          spot_price: 24_500, strike_price: 24_600, option_type: 'CE',
          iv_pct: 15.0, days_to_expiry: 7, strike_step: 50
        )

        expect(delta).to be_between(0.0, 1.0)
        # A real BS delta near-ATM 7DTE should not land exactly on the 0.5 heuristic value
        expect(delta).not_to eq(0.5)
      end

      it 'derives days_to_expiry from expiry_date when days_to_expiry is not given' do
        delta = described_class.estimate_delta(
          spot_price: 24_500, strike_price: 24_600, option_type: 'PE',
          iv_pct: 15.0, expiry_date: 10.days.from_now.to_date, strike_step: 50
        )

        expect(delta).to be_between(0.0, 1.0)
      end
    end

    context 'when IV or DTE is missing' do
      it 'falls back to the legacy within-N-strike-steps-of-ATM heuristic' do
        near_atm = described_class.estimate_delta(
          spot_price: 24_505, strike_price: 24_500, strike_step: 50
        )
        far_otm = described_class.estimate_delta(
          spot_price: 24_505, strike_price: 25_000, strike_step: 50
        )

        expect(near_atm).to eq(0.5)
        expect(far_otm).to eq(0.0)
      end
    end

    it 'falls back gracefully instead of raising when option_type is nonsense' do
      delta = described_class.estimate_delta(
        spot_price: 24_500, strike_price: 24_500, option_type: 'bogus',
        iv_pct: 15.0, days_to_expiry: 7, strike_step: 50
      )

      expect(delta).to eq(0.5) # ATM legacy fallback, no exception raised
    end

    it 'returns 0.0 when spot/strike/strike_step are unusable' do
      expect(described_class.estimate_delta(spot_price: nil, strike_price: 100, strike_step: 50)).to eq(0.0)
    end
  end

  describe '.dte_from' do
    it 'computes whole days between today and the expiry date' do
      expect(described_class.dte_from(5.days.from_now.to_date)).to eq(5)
    end

    it 'returns nil for blank input' do
      expect(described_class.dte_from(nil)).to be_nil
    end
  end
end
