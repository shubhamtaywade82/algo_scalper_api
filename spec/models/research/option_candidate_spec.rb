# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Research::OptionCandidate do
  def make_signal(day)
    Research::Signal.create!(
      underlying_symbol: 'NIFTY', signal_timestamp: Time.zone.parse("#{day} 10:14:00"),
      direction: 'bullish', spot_price: 24_982
    )
  end

  def make_candidate(signal)
    described_class.create!(
      research_signal: signal, underlying_symbol: 'NIFTY', expiry_flag: 'WEEK', option_type: 'CE',
      strike_label: 'ATM', strike_distance: 0, actual_strike: 25_000, entry_model: 'next_candle_open'
    )
  end

  def make_bar(ts)
    Research::OptionBar.create!(
      underlying_symbol: 'NIFTY', exchange_segment: 'NSE_FNO', expiry_flag: 'WEEK', option_type: 'CE',
      strike_label: 'ATM', interval: '5', ts: ts, open: 100, high: 105, low: 98, close: 101
    )
  end

  describe '#bars' do
    it 'does not blend bars from an unrelated later session into a different day\'s candidate' do
      day1_signal = make_signal('2026-07-10')
      day1_candidate = make_candidate(day1_signal)
      make_bar(Time.zone.parse('2026-07-10 10:15:00'))

      day2_signal = make_signal('2026-08-01')
      make_candidate(day2_signal)
      make_bar(Time.zone.parse('2026-08-01 10:15:00'))

      expect(day1_candidate.bars.map(&:ts)).to eq([Time.zone.parse('2026-07-10 10:15:00')])
    end

    it 'does not blend bars from a different interval for the same contract identity' do
      signal = make_signal('2026-07-10')
      candidate = make_candidate(signal)
      make_bar(Time.zone.parse('2026-07-10 10:15:00'))
      Research::OptionBar.create!(
        underlying_symbol: 'NIFTY', exchange_segment: 'NSE_FNO', expiry_flag: 'WEEK', option_type: 'CE',
        strike_label: 'ATM', interval: '1', ts: Time.zone.parse('2026-07-10 10:16:00'),
        open: 100, high: 105, low: 98, close: 101
      )

      expect(candidate.bars.map(&:interval)).to eq(['5'])
    end
  end
end
