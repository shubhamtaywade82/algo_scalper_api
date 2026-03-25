# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Options::ChainSignalExtractor do
  let(:expiry_date) { 1.week.from_now.to_date }
  let(:chain_data) do
    {
      last_price: 24_500.0,
      oc: {
        24_500.0 => {
          'ce' => { 'oi' => 1_200_000, 'last_price' => 120.0, 'volume' => 50_000 },
          'pe' => { 'oi' => 900_000, 'last_price' => 95.0, 'volume' => 40_000 }
        }
      }
    }
  end

  describe '#call' do
    it 'returns neutral-like result when chain is blank' do
      result = described_class.new(
        index_key: 'NIFTY',
        expiry_date: expiry_date,
        chain_data: nil,
        final_direction: :bullish
      ).call

      expect(result.direction_hint).to eq(:neutral)
      expect(result.direction_confidence).to eq(0)
    end

    it 'computes PCR and bounded confidence for valid chain' do
      result = described_class.new(
        index_key: 'NIFTY',
        expiry_date: expiry_date,
        chain_data: chain_data,
        final_direction: :bullish,
        atm_strike: 24_500.0
      ).call

      expect(result.pcr).to be_within(0.01).of(0.75)
      expect(result.direction_confidence).to be > 0
    end
  end
end
