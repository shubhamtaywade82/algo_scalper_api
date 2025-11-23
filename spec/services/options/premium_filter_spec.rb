# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Options::PremiumFilter do
  describe '#initialize' do
    it 'initializes with index key' do
      filter = described_class.new(index_key: :NIFTY)
      expect(filter.index_key).to eq(:NIFTY)
      expect(filter.rules).to be_a(Options::IndexRules::Nifty)
    end

    it 'raises error for unknown index' do
      expect { described_class.new(index_key: :UNKNOWN) }.to raise_error(ArgumentError, /Unknown index/)
    end

    it 'accepts string index key' do
      filter = described_class.new(index_key: 'BANKNIFTY')
      expect(filter.index_key).to eq(:BANKNIFTY)
      expect(filter.rules).to be_a(Options::IndexRules::Banknifty)
    end
  end

  describe '#valid?' do
    let(:filter) { described_class.new(index_key: :NIFTY) }

    context 'with valid candidate' do
      let(:candidate) do
        {
          premium: 50.0, # Above min_premium (25)
          ltp: 50.0,
          bid: 49.85,        # Tight spread: (50.0-49.85)/50.0 = 0.003 = 0.3% (max allowed)
          ask: 50.0,
          volume: 50_000,    # Above min_volume (30_000)
          oi: 100_000
        }
      end

      it 'returns true' do
        expect(filter.valid?(candidate)).to be true
      end
    end

    context 'with premium below minimum' do
      let(:candidate) do
        {
          premium: 20.0, # Below min_premium (25)
          ltp: 20.0,
          bid: 19.0,
          ask: 21.0,
          volume: 50_000,
          oi: 100_000
        }
      end

      it 'returns false' do
        expect(filter.valid?(candidate)).to be false
      end
    end

    context 'with insufficient liquidity' do
      let(:candidate) do
        {
          premium: 50.0,
          ltp: 50.0,
          bid: 49.0,
          ask: 51.0,
          volume: 20_000,    # Below min_volume (30_000)
          oi: 10_000
        }
      end

      it 'returns false' do
        expect(filter.valid?(candidate)).to be false
      end
    end

    context 'with spread too wide' do
      let(:candidate) do
        {
          premium: 50.0,
          ltp: 50.0,
          bid: 49.0,         # Wide spread
          ask: 51.0, # Spread = (51-49)/51 = 0.0392 = 3.92% > max_spread (0.003 = 0.3%)
          volume: 50_000,
          oi: 100_000
        }
      end

      it 'returns false' do
        expect(filter.valid?(candidate)).to be false
      end
    end

    context 'with missing premium but valid ltp' do
      let(:candidate) do
        {
          ltp: 50.0,         # Used as premium fallback
          bid: 49.85,        # Tight spread
          ask: 50.0,
          volume: 50_000,
          oi: 100_000
        }
      end

      it 'uses ltp as premium and returns true' do
        expect(filter.valid?(candidate)).to be true
      end
    end

    context 'with invalid candidate' do
      it 'returns false for nil' do
        expect(filter.valid?(nil)).to be false
      end

      it 'returns false for non-hash' do
        expect(filter.valid?('invalid')).to be false
      end
    end

    context 'with BANKNIFTY rules' do
      let(:banknifty_filter) { described_class.new(index_key: :BANKNIFTY) }

      it 'uses BANKNIFTY min_premium (40)' do
        candidate = {
          premium: 35.0,     # Below BANKNIFTY min (40)
          ltp: 35.0,
          bid: 34.0,
          ask: 36.0,
          volume: 60_000,    # Above min_volume (50_000)
          oi: 100_000
        }
        expect(banknifty_filter.valid?(candidate)).to be false
      end

      it 'uses BANKNIFTY min_volume (50_000)' do
        candidate = {
          premium: 50.0,
          ltp: 50.0,
          bid: 49.0,
          ask: 51.0,
          volume: 40_000,    # Below BANKNIFTY min (50_000)
          oi: 100_000
        }
        expect(banknifty_filter.valid?(candidate)).to be false
      end
    end

    context 'with SENSEX rules' do
      let(:sensex_filter) { described_class.new(index_key: :SENSEX) }

      it 'uses SENSEX min_premium (30)' do
        candidate = {
          premium: 25.0,     # Below SENSEX min (30)
          ltp: 25.0,
          bid: 24.0,
          ask: 26.0,
          volume: 30_000,    # Above min_volume (20_000)
          oi: 100_000
        }
        expect(sensex_filter.valid?(candidate)).to be false
      end
    end
  end

  describe '#validate_with_details' do
    let(:filter) { described_class.new(index_key: :NIFTY) }

    context 'with valid candidate' do
      let(:candidate) do
        {
          premium: 50.0,
          ltp: 50.0,
          bid: 49.85,        # Tight spread: (50.0-49.85)/50.0 = 0.003 = 0.3% (max allowed)
          ask: 50.0,
          volume: 50_000,
          oi: 100_000
        }
      end

      # rubocop:disable RSpec/MultipleExpectations
      it 'returns detailed validation with all checks passing' do
        result = filter.validate_with_details(candidate)
        expect(result[:valid]).to be true
        expect(result[:premium_check]).to be true
        expect(result[:liquidity_check]).to be true
        expect(result[:spread_check]).to be true
        expect(result[:reason]).to eq('valid')
      end
      # rubocop:enable RSpec/MultipleExpectations
    end

    context 'with invalid candidate' do
      let(:candidate) do
        {
          premium: 20.0,     # Below min
          ltp: 20.0,
          bid: 19.0,
          ask: 21.0,
          volume: 20_000,    # Below min
          oi: 10_000
        }
      end

      # rubocop:disable RSpec/MultipleExpectations
      it 'returns detailed validation with failure reasons' do
        result = filter.validate_with_details(candidate)
        expect(result[:valid]).to be false
        expect(result[:premium_check]).to be false
        expect(result[:liquidity_check]).to be false
        expect(result[:reason]).to include('premium_below_min')
        expect(result[:reason]).to include('insufficient_liquidity')
      end
      # rubocop:enable RSpec/MultipleExpectations
    end

    context 'with missing data' do
      it 'handles nil candidate gracefully' do
        result = filter.validate_with_details(nil)
        expect(result[:valid]).to be false
        expect(result[:reason]).to eq('invalid_candidate')
      end
    end
  end

  describe 'private methods' do
    let(:filter) { described_class.new(index_key: :NIFTY) }

    describe '#premium_in_band?' do
      it 'returns true for premium >= min_premium' do
        expect(filter.send(:premium_in_band?, 50.0)).to be true
        expect(filter.send(:premium_in_band?, 25.0)).to be true
      end

      it 'returns false for premium < min_premium' do
        expect(filter.send(:premium_in_band?, 20.0)).to be false
      end

      it 'returns false for nil or zero premium' do
        expect(filter.send(:premium_in_band?, nil)).to be false
        expect(filter.send(:premium_in_band?, 0.0)).to be false
      end
    end

    describe '#liquidity_ok?' do
      it 'returns true for volume >= min_volume' do
        candidate = { volume: 50_000 }
        expect(filter.send(:liquidity_ok?, candidate)).to be true
      end

      it 'returns false for volume < min_volume' do
        candidate = { volume: 20_000 }
        expect(filter.send(:liquidity_ok?, candidate)).to be false
      end

      it 'uses oi as fallback if volume missing' do
        candidate = { oi: 50_000 }
        expect(filter.send(:liquidity_ok?, candidate)).to be true
      end
    end

    describe '#spread_ok?' do
      it 'returns true for spread <= max_spread_pct' do
        candidate = { bid: 49.85, ask: 50.0, ltp: 50.0 }
        # Spread = (50.0-49.85)/50.0 = 0.003 = 0.3% (max allowed)
        expect(filter.send(:spread_ok?, candidate)).to be true
      end

      it 'returns false for spread > max_spread_pct' do
        candidate = { bid: 45.0, ask: 55.0, ltp: 50.0 }
        expect(filter.send(:spread_ok?, candidate)).to be false
      end

      it 'handles missing bid/ask' do
        candidate = { ltp: 50.0 }
        expect(filter.send(:spread_ok?, candidate)).to be false
      end
    end

    describe '#calculate_spread' do
      it 'calculates spread correctly as decimal' do
        spread = filter.send(:calculate_spread, 49.85, 50.0, 50.0)
        # (50.0-49.85)/50.0 = 0.003 = 0.3%
        expect(spread).to be_within(0.0001).of(0.003)
      end

      it 'returns nil for missing bid/ask' do
        expect(filter.send(:calculate_spread, nil, 51.0, 50.0)).to be_nil
        expect(filter.send(:calculate_spread, 49.0, nil, 50.0)).to be_nil
      end

      it 'returns nil for zero bid/ask' do
        expect(filter.send(:calculate_spread, 0.0, 51.0, 50.0)).to be_nil
        expect(filter.send(:calculate_spread, 49.0, 0.0, 50.0)).to be_nil
      end
    end
  end
end
