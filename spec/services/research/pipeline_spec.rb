# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Research::Pipeline do
  let(:signal) do
    Research::Signal.create!(
      underlying_symbol: 'NIFTY',
      signal_timestamp: Time.zone.parse('2026-07-10 10:14:00'),
      direction: 'bullish',
      spot_price: 24_982
    )
  end

  describe '.run' do
    before do
      allow(Research::OptionCandleFetcher).to receive(:call) do |symbol:, option_type:, expiry_flag:, strike_label:, **|
        Research::OptionBar.create!(
          underlying_symbol: symbol, exchange_segment: 'NSE_FNO', expiry_flag: expiry_flag,
          option_type: option_type, strike_label: strike_label, interval: '5',
          ts: Time.zone.parse('2026-07-10 10:15:00'), open: 110, high: 120, low: 108, close: 118, volume: 100_000
        )
      end
    end

    it 'builds candidates, fetches bars for each, and returns them ranked by return_pct' do
      ranked = described_class.run(signal: signal, expiry_flags: ['WEEK'], max_distance: 1)

      expect(ranked.size).to eq(3)
      expect(ranked).to all(have_attributes(status: 'scored'))
      expect(Research::OptionCandleFetcher).to have_received(:call).exactly(3).times
      expect(ranked.each_cons(2).all? { |a, b| a.return_pct >= b.return_pct }).to be true
    end

    it 'returns an empty array when the signal has no direction to trade' do
      signal.update!(direction: 'no_trade')
      expect(described_class.run(signal: signal)).to eq([])
      expect(Research::OptionCandleFetcher).not_to have_received(:call)
    end
  end
end
