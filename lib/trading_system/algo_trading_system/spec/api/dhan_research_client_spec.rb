# frozen_string_literal: true

require 'spec_helper'
require_relative '../../src/api/dhan_research_client'

RSpec.describe Api::DhanResearchClient do
  let(:access_token) { 'test_token' }
  let(:client) { described_class.new(access_token: access_token) }

  describe '#fetch_spot_intraday' do
    it 'fetches and merges intraday data chunks' do
      # Mock the gem's call
      allow(DhanHQ::Models::HistoricalData).to receive(:intraday).and_return(
        {
          'timestamp' => [1704080000, 1704080060],
          'open' => [100.0, 101.0],
          'high' => [102.0, 103.0],
          'low' => [99.0, 100.0],
          'close' => [101.0, 102.0],
          'volume' => [1000, 1100]
        }
      )

      result = client.fetch_spot_intraday(
        security_id: 13,
        from_date: '2024-01-01',
        to_date: '2024-01-01'
      )

      expect(result[:timestamp]).to include(1704080000)
      expect(result[:close]).to eq([101.0, 102.0])
    end
  end

  describe '#fetch_rolling_options' do
    it 'fetches and merges rolling options data' do
      allow(DhanHQ::Models::ExpiredOptionsData).to receive(:fetch).and_return(
        {
          'data' => {
            'ce' => {
              'timestamp' => [1704080000],
              'open' => [50.0],
              'high' => [55.0],
              'low' => [45.0],
              'close' => [52.0],
              'volume' => [500],
              'iv' => [15.5],
              'oi' => [10000],
              'strike' => [21500],
              'spot' => [21520]
            }
          }
        }
      )

      result = client.fetch_rolling_options(
        security_id: 13,
        option_type: 'CALL',
        from_date: '2024-01-01',
        to_date: '2024-01-01'
      )

      expect(result[:timestamp]).to include(1704080000)
      expect(result[:iv]).to eq([15.5])
    end
  end
end
