# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Options::StrikeSelector do
  let(:selector) { described_class.new }
  let(:mock_analyzer) { instance_double(Options::DerivativeChainAnalyzer) }
  let(:mock_premium_filter) { instance_double(Options::PremiumFilter) }
  let(:mock_rules) { instance_double(Options::IndexRules::Nifty) }

  before do
    allow(Options::DerivativeChainAnalyzer).to receive(:new).and_return(mock_analyzer)
    allow(Options::PremiumFilter).to receive(:new).and_return(mock_premium_filter)
    allow(Live::TickCache).to receive(:ltp).and_return(25_000.0)
    allow(mock_premium_filter).to receive(:valid?).and_return(true)

    # Mock AlgoConfig for spot price lookup
    allow(AlgoConfig).to receive(:fetch).and_return(
      indices: [
        { key: 'NIFTY', segment: 'NSE_INDEX', sid: '26000' }
      ]
    )

    # Mock IndexRules
    allow(Options::IndexRules::Nifty).to receive(:new).and_return(mock_rules)
    allow(mock_rules).to receive(:atm).with(25_000.0).and_return(25_000.0)
    allow(mock_rules).to receive_messages(
      lot_size: 75,
      multiplier: 1,
      valid_liquidity?: true,
      valid_spread?: true,
      valid_premium?: true
    )
    allow(mock_rules).to receive(:candidate_strikes).with(25_000.0, anything).and_return([25_000.0, 25_050.0])
  end

  describe '#select' do
    context 'with valid candidates' do
      let(:candidate) do
        {
          derivative: instance_double(Derivative),
          strike: 25_000.0,
          type: 'CE',
          segment: 'NSE_FNO',
          security_id: '49081',
          lot_size: 75,
          ltp: 150.5,
          iv: 20.5,
          oi: 500_000,
          bid: 150.0,
          ask: 151.0,
          volume: 50_000,
          score: 0.85,
          symbol: 'NIFTY-25Jan2024-25000-CE',
          derivative_id: 123,
          reason: 'High score'
        }
      end

      before do
        allow(mock_analyzer).to receive(:select_candidates).and_return([candidate])
        # Stub spot price lookup (for index)
        allow(Live::TickCache).to receive(:ltp).with('NSE_INDEX', '26000').and_return(25_000.0)
        # Stub LTP lookup for derivative (returns nil, so falls back to candidate[:ltp])
        allow(Live::TickCache).to receive(:ltp).with('NSE_FNO', '49081').and_return(nil)
        allow(Live::RedisTickCache.instance).to receive(:fetch_tick).and_return(nil)
      end

      it 'returns normalized instrument hash' do
        result = selector.select(index_key: 'NIFTY', direction: :bullish)

        expect(result).to be_a(Hash)
        expect(result[:index]).to eq('NIFTY')
        expect(result[:strike]).to eq(25_000)
        expect(result[:option_type]).to eq('CE')
      end

      it 'includes required fields in normalized hash' do
        result = selector.select(index_key: 'NIFTY', direction: :bullish)

        expect(result[:ltp]).to eq(150.5)
        expect(result[:lot_size]).to eq(75)
        expect(result[:security_id]).to eq('49081')
      end

      it 'includes OTM depth information' do
        result = selector.select(index_key: 'NIFTY', direction: :bullish)

        expect(result[:otm_depth]).to be_a(Integer)
        expect(result[:max_otm_allowed]).to be_a(Integer)
      end
    end

    context 'with trend score determining OTM depth' do
      let(:atm_candidate) do
        {
          derivative: instance_double(Derivative),
          strike: 25_000.0, # ATM
          type: 'CE',
          segment: 'NSE_FNO',
          security_id: '49081',
          ltp: 150.5,
          bid: 150.0,
          ask: 151.0,
          volume: 50_000,
          oi: 500_000
        }
      end

      let(:otm1_candidate) do
        {
          derivative: instance_double(Derivative),
          strike: 25_050.0, # 1OTM
          type: 'CE',
          segment: 'NSE_FNO',
          security_id: '49082',
          ltp: 120.0,
          bid: 119.0,
          ask: 121.0,
          volume: 40_000,
          oi: 400_000
        }
      end

      let(:otm2_candidate) do
        {
          derivative: instance_double(Derivative),
          strike: 25_100.0, # 2OTM
          type: 'CE',
          segment: 'NSE_FNO',
          security_id: '49083',
          ltp: 100.0,
          bid: 99.0,
          ask: 101.0,
          volume: 30_000,
          oi: 300_000
        }
      end

      before do
        allow(Live::TickCache).to receive(:ltp).with('NSE_INDEX', '26000').and_return(25_025.0) # Spot price
        allow(mock_rules).to receive(:atm).with(25_025.0).and_return(25_000.0)
        allow(mock_rules).to receive(:candidate_strikes).with(25_000.0,
                                                              anything).and_return([25_000.0, 25_050.0, 25_100.0])
        allow(Live::RedisTickCache.instance).to receive(:fetch_tick).and_return(nil)
      end

      it 'allows only ATM when trend_score is low' do
        allow(mock_analyzer).to receive(:select_candidates).and_return([atm_candidate, otm1_candidate, otm2_candidate])
        allow(mock_premium_filter).to receive(:valid?).with(atm_candidate).and_return(true)
        allow(mock_premium_filter).to receive(:valid?).with(otm1_candidate).and_return(false)
        allow(mock_premium_filter).to receive(:valid?).with(otm2_candidate).and_return(false)

        result = selector.select(index_key: 'NIFTY', direction: :bullish, trend_score: 10.0)

        expect(result).not_to be_nil
        expect(result[:strike]).to eq(25_000.0) # ATM only
        expect(result[:max_otm_allowed]).to eq(0)
      end

      it 'allows 1OTM when trend_score >= 12' do
        allow(mock_analyzer).to receive(:select_candidates).and_return([atm_candidate, otm1_candidate])
        allow(mock_premium_filter).to receive(:valid?).with(atm_candidate).and_return(false)
        allow(mock_premium_filter).to receive(:valid?).with(otm1_candidate).and_return(true)

        result = selector.select(index_key: 'NIFTY', direction: :bullish, trend_score: 15.0)

        expect(result).not_to be_nil
        expect(result[:strike]).to eq(25_050.0) # 1OTM
        expect(result[:max_otm_allowed]).to eq(1)
      end

      it 'allows 2OTM when trend_score >= 18' do
        allow(mock_analyzer).to receive(:select_candidates).and_return([atm_candidate, otm1_candidate, otm2_candidate])
        allow(mock_premium_filter).to receive(:valid?).with(atm_candidate).and_return(false)
        allow(mock_premium_filter).to receive(:valid?).with(otm1_candidate).and_return(false)
        allow(mock_premium_filter).to receive(:valid?).with(otm2_candidate).and_return(true)

        result = selector.select(index_key: 'NIFTY', direction: :bullish, trend_score: 20.0)

        expect(result).not_to be_nil
        expect(result[:strike]).to eq(25_100.0) # 2OTM
        expect(result[:max_otm_allowed]).to eq(2)
      end
    end

    context 'when no candidates from analyzer' do
      before do
        allow(mock_analyzer).to receive(:select_candidates).and_return([])
      end

      it 'returns nil' do
        result = selector.select(index_key: 'NIFTY', direction: :bullish)
        expect(result).to be_nil
      end
    end

    context 'when candidate fails index rules' do
      let(:invalid_candidate) do
        {
          strike: 25_000.0,
          type: 'CE',
          segment: 'NSE_FNO',
          security_id: '49081',
          lot_size: 75,
          ltp: 10.0, # Below minimum premium
          volume: 5_000, # Below minimum volume
          bid: 9.0,
          ask: 11.0
        }
      end

      before do
        allow(mock_analyzer).to receive(:select_candidates).and_return([invalid_candidate])
        allow(mock_premium_filter).to receive(:valid?).and_return(false)
      end

      it 'returns nil' do
        result = selector.select(index_key: 'NIFTY', direction: :bullish)
        expect(result).to be_nil
      end
    end

    context 'when candidates are filtered out by strike distance' do
      let(:deep_otm_candidate) do
        {
          derivative: instance_double(Derivative),
          strike: 26_000.0, # Deep OTM (not allowed)
          type: 'CE',
          segment: 'NSE_FNO',
          security_id: '49081',
          ltp: 50.0,
          bid: 49.0,
          ask: 51.0,
          volume: 50_000,
          oi: 500_000
        }
      end

      before do
        allow(mock_analyzer).to receive(:select_candidates).and_return([deep_otm_candidate])
        allow(Live::TickCache).to receive(:ltp).with('NSE_INDEX', '26000').and_return(25_000.0)
        allow(Live::RedisTickCache.instance).to receive(:fetch_tick).and_return(nil)
      end

      it 'returns nil when no candidates within allowed strike distance' do
        result = selector.select(index_key: 'NIFTY', direction: :bullish, trend_score: 10.0)
        expect(result).to be_nil
      end
    end

    context 'with unknown index' do
      it 'returns nil (error is caught and logged)' do
        # SelectionError is caught and returns nil
        result = selector.select(index_key: 'UNKNOWN', direction: :bullish)
        expect(result).to be_nil
      end
    end

    context 'with bearish direction (PE options)' do
      let(:pe_candidate) do
        {
          derivative: instance_double(Derivative),
          strike: 24_950.0, # 1OTM below ATM for PE
          type: 'PE',
          segment: 'NSE_FNO',
          security_id: '49081',
          ltp: 150.5,
          bid: 150.0,
          ask: 151.0,
          volume: 50_000,
          oi: 500_000
        }
      end

      before do
        allow(mock_analyzer).to receive(:select_candidates).and_return([pe_candidate])
        allow(Live::TickCache).to receive(:ltp).with('NSE_INDEX', '26000').and_return(25_000.0)
        allow(mock_rules).to receive(:candidate_strikes).with(25_000.0, anything).and_return([25_000.0, 24_950.0])
        allow(Live::RedisTickCache.instance).to receive(:fetch_tick).and_return(nil)
      end

      it 'selects PE strikes below ATM' do
        result = selector.select(index_key: 'NIFTY', direction: :bearish, trend_score: 15.0)

        expect(result).not_to be_nil
        expect(result[:option_type]).to eq('PE')
        expect(result[:strike]).to eq(24_950.0)
      end
    end
  end

  describe 'private methods' do
    describe '#calculate_max_otm_depth' do
      it 'returns 0 for nil trend_score' do
        depth = selector.send(:calculate_max_otm_depth, nil)
        expect(depth).to eq(0)
      end

      it 'returns 0 for low trend_score' do
        depth = selector.send(:calculate_max_otm_depth, 10.0)
        expect(depth).to eq(0)
      end

      it 'returns 1 for trend_score >= 12' do
        depth = selector.send(:calculate_max_otm_depth, 12.0)
        expect(depth).to eq(1)
      end

      it 'returns 2 for trend_score >= 18' do
        depth = selector.send(:calculate_max_otm_depth, 18.0)
        expect(depth).to eq(2)
      end
    end

    describe '#calculate_allowed_strikes' do
      let(:rules) { Options::IndexRules::Nifty.new }

      it 'returns only ATM for max_otm_depth = 0' do
        strikes = selector.send(:calculate_allowed_strikes, 25_000.0, 0, :bullish, rules)
        expect(strikes).to eq([25_000.0])
      end

      it 'returns ATM and 1OTM for max_otm_depth = 1 (bullish)' do
        strikes = selector.send(:calculate_allowed_strikes, 25_000.0, 1, :bullish, rules)
        expect(strikes).to eq([25_000.0, 25_050.0])
      end

      it 'returns ATM, 1OTM, and 2OTM for max_otm_depth = 2 (bullish)' do
        strikes = selector.send(:calculate_allowed_strikes, 25_000.0, 2, :bullish, rules)
        expect(strikes).to eq([25_000.0, 25_050.0, 25_100.0])
      end

      it 'returns ATM and 1OTM below for bearish direction' do
        strikes = selector.send(:calculate_allowed_strikes, 25_000.0, 1, :bearish, rules)
        expect(strikes).to eq([25_000.0, 24_950.0])
      end
    end
  end
end
