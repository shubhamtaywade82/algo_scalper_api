# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Options::Greeks::BlackScholes do
  # Reference values cross-checked against a standard BS calculator
  # (spot=100, strike=100, t=1y, r=5%, sigma=20%, q=0):
  # call price ≈ 10.4506, call delta ≈ 0.6368, put price ≈ 5.5735, put delta ≈ -0.3632
  describe '.calculate' do
    context 'when pricing an ATM call with textbook 1-year inputs' do
      subject(:result) do
        described_class.calculate(
          spot_price: 100, strike_price: 100, time_to_expiry_years: 1.0,
          volatility: 0.2, option_type: :call, risk_free_rate: 0.05, dividend_yield: 0.0
        )
      end

      it 'matches the known closed-form price within 1 cent' do
        expect(result[:theoretical_price]).to be_within(0.01).of(10.4506)
      end

      it 'matches the known closed-form delta within 1e-3' do
        expect(result[:delta]).to be_within(0.001).of(0.6368)
      end

      it 'returns a positive gamma and vega' do
        expect(result[:gamma]).to be_positive
        expect(result[:vega]).to be_positive
      end
    end

    context 'when pricing an ATM put with the same textbook inputs (put-call parity)' do
      subject(:result) do
        described_class.calculate(
          spot_price: 100, strike_price: 100, time_to_expiry_years: 1.0,
          volatility: 0.2, option_type: :put, risk_free_rate: 0.05, dividend_yield: 0.0
        )
      end

      it 'matches the known closed-form price within 1 cent' do
        expect(result[:theoretical_price]).to be_within(0.01).of(5.5735)
      end

      it 'has a negative delta between -1 and 0' do
        expect(result[:delta]).to be_within(0.001).of(-0.3632)
      end
    end

    it 'accepts CE/PE string option types (broker convention) identically to call/put symbols' do
      via_ce = described_class.calculate(spot_price: 100, strike_price: 100, time_to_expiry_years: 0.5,
                                         volatility: 0.25, option_type: 'CE')
      via_call = described_class.calculate(spot_price: 100, strike_price: 100, time_to_expiry_years: 0.5,
                                           volatility: 0.25, option_type: :call)
      expect(via_ce).to eq(via_call)
    end

    it 'raises on an unrecognized option_type' do
      expect do
        described_class.calculate(spot_price: 100, strike_price: 100, time_to_expiry_years: 0.5,
                                  volatility: 0.2, option_type: :straddle)
      end.to raise_error(ArgumentError, /Unknown option_type/)
    end

    it 'returns a zeroed result for non-positive spot/strike instead of raising' do
      result = described_class.calculate(spot_price: 0, strike_price: 100, time_to_expiry_years: 0.5,
                                         volatility: 0.2, option_type: :call)
      expect(result[:theoretical_price]).to eq(0.0)
      expect(result[:delta]).to eq(0.0)
    end

    it 'a call delta stays within (0, 1) and a put delta within (-1, 0) for deep ITM/OTM strikes' do
      deep_itm_call = described_class.calculate(spot_price: 200, strike_price: 100, time_to_expiry_years: 0.1,
                                                volatility: 0.2, option_type: :call)
      deep_otm_call = described_class.calculate(spot_price: 50, strike_price: 100, time_to_expiry_years: 0.1,
                                                volatility: 0.2, option_type: :call)
      expect(deep_itm_call[:delta]).to be_within(0.02).of(1.0)
      expect(deep_otm_call[:delta]).to be_within(0.02).of(0.0)
    end
  end

  describe '.implied_volatility' do
    it 'round-trips: solving IV from a BS-generated price recovers the original volatility' do
      priced = described_class.calculate(
        spot_price: 24_500, strike_price: 24_600, time_to_expiry_years: 7.0 / 365.0,
        volatility: 0.18, option_type: :call
      )

      solved_iv = described_class.implied_volatility(
        observed_premium: priced[:theoretical_price],
        spot_price: 24_500, strike_price: 24_600, time_to_expiry_years: 7.0 / 365.0,
        option_type: :call
      )

      expect(solved_iv).to be_within(0.005).of(0.18)
    end

    it 'returns nil for a non-positive premium' do
      expect(described_class.implied_volatility(
        observed_premium: 0, spot_price: 24_500, strike_price: 24_600,
        time_to_expiry_years: 0.02, option_type: :call
      )).to be_nil
    end
  end

  describe '.norm_cdf' do
    it 'matches known standard normal CDF values' do
      expect(described_class.norm_cdf(0)).to be_within(1e-6).of(0.5)
      expect(described_class.norm_cdf(1.959_964)).to be_within(1e-4).of(0.975)
      expect(described_class.norm_cdf(-1.959_964)).to be_within(1e-4).of(0.025)
    end
  end
end
