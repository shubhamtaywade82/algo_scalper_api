# frozen_string_literal: true

require 'rails_helper'

RSpec.describe IvSnapshot do
  describe '.historical_iv' do
    let(:index_key) { 'nifty' }

    before do
      # Snapshot within last 30 days
      described_class.create!(
        index_key: index_key,
        snapshot_date: 5.days.ago.to_date,
        implied_volatility: 14.5,
        strike_price: 24_000,
        option_type: 'CE'
      )
      described_class.create!(
        index_key: index_key,
        snapshot_date: 10.days.ago.to_date,
        implied_volatility: 15.0,
        strike_price: 24_000,
        option_type: 'PE'
      )
      # Stale snapshot older than 30 days
      described_class.create!(
        index_key: index_key,
        snapshot_date: 45.days.ago.to_date,
        implied_volatility: 22.0,
        strike_price: 24_000,
        option_type: 'CE'
      )
      # Different index
      described_class.create!(
        index_key: 'banknifty',
        snapshot_date: 2.days.ago.to_date,
        implied_volatility: 18.0,
        strike_price: 50_000,
        option_type: 'CE'
      )
    end

    it 'returns snapshots within the date window and excludes stale records' do
      ivs = described_class.historical_iv(index_key: index_key, days: 30)

      expect(ivs).to contain_exactly(14.5, 15.0)
      expect(ivs).not_to include(22.0)
      expect(ivs).not_to include(18.0)
    end

    it 'returns empty array when all snapshots are older than days window' do
      ivs = described_class.historical_iv(index_key: index_key, days: 3)
      expect(ivs).to be_empty
    end
  end

  describe '.latest_for' do
    it 'returns the most recent snapshot for the specified index' do
      described_class.create!(
        index_key: 'banknifty',
        snapshot_date: 5.days.ago.to_date,
        implied_volatility: 16.0,
        strike_price: 50_000,
        option_type: 'CE'
      )
      latest = described_class.create!(
        index_key: 'banknifty',
        snapshot_date: 1.day.ago.to_date,
        implied_volatility: 17.5,
        strike_price: 50_000,
        option_type: 'CE'
      )

      expect(described_class.latest_for(index_key: 'banknifty')).to eq(latest)
    end
  end
end
