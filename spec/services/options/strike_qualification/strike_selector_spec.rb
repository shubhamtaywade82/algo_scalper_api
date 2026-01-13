# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Options::StrikeQualification::StrikeSelector do
  subject(:selector) { described_class.new }

  let(:nifty_chain) do
    {
      '24950' => {
        'ce' => { 'last_price' => 80, 'oi' => 100_000, 'top_bid_price' => 79, 'top_ask_price' => 81 },
        'pe' => { 'last_price' => 120, 'oi' => 100_000, 'top_bid_price' => 119, 'top_ask_price' => 121 }
      },
      '25000' => {
        'ce' => { 'last_price' => 100, 'oi' => 100_000, 'top_bid_price' => 99, 'top_ask_price' => 101 },
        'pe' => { 'last_price' => 100, 'oi' => 100_000, 'top_bid_price' => 99, 'top_ask_price' => 101 }
      },
      '25050' => {
        'ce' => { 'last_price' => 90, 'oi' => 100_000, 'top_bid_price' => 89, 'top_ask_price' => 91 },
        'pe' => { 'last_price' => 130, 'oi' => 100_000, 'top_bid_price' => 129, 'top_ask_price' => 131 }
      }
    }
  end

  let(:sensex_chain) do
    {
      '80000' => {
        'ce' => { 'last_price' => 200, 'oi' => 50_000, 'top_bid_price' => 198, 'top_ask_price' => 202 },
        'pe' => { 'last_price' => 210, 'oi' => 50_000, 'top_bid_price' => 208, 'top_ask_price' => 212 }
      },
      '80100' => {
        'ce' => { 'last_price' => 170, 'oi' => 50_000, 'top_bid_price' => 168, 'top_ask_price' => 172 },
        'pe' => { 'last_price' => 240, 'oi' => 50_000, 'top_bid_price' => 238, 'top_ask_price' => 242 }
      }
    }
  end

  describe '#call' do
    it 'selects ATM+1 for NIFTY bullish CE' do
      result = selector.call(
        index_key: 'NIFTY',
        side: :CE,
        permission: :scale_ready,
        spot: 25_025,
        option_chain: nifty_chain,
        trend: :bullish
      )

      expect(result[:ok]).to eq(true)
      expect(result[:atm_strike]).to eq(25_000)
      expect(result[:strike]).to eq(25_050)
      expect(result[:strike_type]).to eq(:ATM_PLUS_1)
    end

    it 'selects ATM-1 for NIFTY bearish PE' do
      result = selector.call(
        index_key: 'NIFTY',
        side: :PE,
        permission: :scale_ready,
        spot: 25_025,
        option_chain: nifty_chain,
        trend: :bearish
      )

      expect(result[:ok]).to eq(true)
      expect(result[:atm_strike]).to eq(25_000)
      expect(result[:strike]).to eq(24_950)
      expect(result[:strike_type]).to eq(:ATM_MINUS_1)
    end

    it 'forces ATM in chop context' do
      result = selector.call(
        index_key: 'NIFTY',
        side: :CE,
        permission: :scale_ready,
        spot: 25_025,
        option_chain: nifty_chain,
        trend: :chop
      )

      expect(result[:ok]).to eq(true)
      expect(result[:strike]).to eq(25_000)
      expect(result[:strike_type]).to eq(:ATM)
    end

    it 'forces ATM when permission is execution_only' do
      result = selector.call(
        index_key: 'NIFTY',
        side: :CE,
        permission: :execution_only,
        spot: 25_025,
        option_chain: nifty_chain,
        trend: :bullish
      )

      expect(result[:ok]).to eq(true)
      expect(result[:strike]).to eq(25_000)
      expect(result[:strike_type]).to eq(:ATM)
    end

    it 'forces SENSEX ATM when permission is not full_deploy' do
      result = selector.call(
        index_key: 'SENSEX',
        side: :CE,
        permission: :scale_ready,
        spot: 80_050,
        option_chain: sensex_chain,
        trend: :bullish
      )

      expect(result[:ok]).to eq(true)
      expect(result[:atm_strike]).to eq(80_100) # 80050 rounds to 80100 with step=100
      expect(result[:strike]).to eq(80_100)
      expect(result[:strike_type]).to eq(:ATM)
    end

    it 'allows SENSEX ATM+1 only for full_deploy' do
      # Make ATM+1 liquid too
      chain = sensex_chain.merge(
        '80200' => { 'ce' => { 'last_price' => 140, 'oi' => 50_000, 'top_bid_price' => 138, 'top_ask_price' => 142 } }
      )

      result = selector.call(
        index_key: 'SENSEX',
        side: :CE,
        permission: :full_deploy,
        spot: 80_050,
        option_chain: chain,
        trend: :bullish
      )

      expect(result[:ok]).to eq(true)
      expect(result[:atm_strike]).to eq(80_100)
      expect(result[:strike]).to eq(80_200)
      expect(result[:strike_type]).to eq(:ATM_PLUS_1)
    end
  end
end

