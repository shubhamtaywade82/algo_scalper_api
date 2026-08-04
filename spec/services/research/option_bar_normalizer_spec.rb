# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Research::OptionBarNormalizer do
  describe '.normalize' do
    let(:raw_side_data) do
      {
        'timestamp' => [1_752_000_000, 1_752_000_300],
        'open' => [120.5, 122.0],
        'high' => [125.0, 124.0],
        'low' => [119.0, 121.0],
        'close' => [122.0, 123.5],
        'volume' => [1000, 800],
        'oi' => [50_000, 51_000],
        'spot' => [24_982.0, 24_990.0],
        'strike' => [25_000.0, 25_000.0]
      }
    end

    it 'returns one row per timestamp with parsed OHLCV fields' do
      rows = described_class.normalize(
        raw_side_data,
        symbol: 'nifty',
        exchange_segment: 'NSE_FNO',
        expiry_flag: 'WEEK',
        option_type: 'ce',
        strike_label: 'ATM',
        interval: 5
      )

      expect(rows.size).to eq(2)
      expect(rows.first).to include(
        underlying_symbol: 'NIFTY',
        option_type: 'CE',
        strike_label: 'ATM',
        actual_strike: 25_000.0,
        interval: '5',
        open: 120.5,
        close: 122.0,
        volume: 1000,
        oi: 50_000,
        spot: 24_982.0,
        source: 'rolling_option'
      )
      expect(rows.first[:ts]).to be_a(ActiveSupport::TimeWithZone)
    end

    it 'returns an empty array when the payload has no timestamps' do
      expect(described_class.normalize(nil, symbol: 'NIFTY', exchange_segment: 'NSE_FNO', expiry_flag: 'WEEK',
                                            option_type: 'CE', strike_label: 'ATM', interval: 5)).to eq([])
      expect(described_class.normalize({}, symbol: 'NIFTY', exchange_segment: 'NSE_FNO', expiry_flag: 'WEEK',
                                           option_type: 'CE', strike_label: 'ATM', interval: 5)).to eq([])
    end
  end
end
