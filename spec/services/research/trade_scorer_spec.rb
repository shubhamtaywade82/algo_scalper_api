# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Research::TradeScorer do
  let(:signal) do
    Research::Signal.create!(
      underlying_symbol: 'NIFTY',
      signal_timestamp: Time.zone.parse('2026-07-10 10:14:00'),
      direction: 'bullish',
      spot_price: 24_982
    )
  end

  let(:candidate) do
    Research::OptionCandidate.create!(
      research_signal: signal,
      underlying_symbol: 'NIFTY',
      expiry_flag: 'WEEK',
      option_type: 'CE',
      strike_label: 'ATM',
      strike_distance: 0,
      actual_strike: 25_000,
      entry_model: 'next_candle_open'
    )
  end

  def bar!(ts:, open:, high:, low:, close:)
    Research::OptionBar.create!(
      underlying_symbol: 'NIFTY', exchange_segment: 'NSE_FNO', expiry_flag: 'WEEK', option_type: 'CE',
      strike_label: 'ATM', interval: '5', ts: ts, open: open, high: high, low: low, close: close
    )
  end

  describe '.score!' do
    it 'marks no_data when there are no bars' do
      described_class.score!(candidate)
      expect(candidate.reload.status).to eq('no_data')
    end

    it 'enters at the first bar after the signal timestamp and scores MFE/MAE/return' do
      bar!(ts: Time.zone.parse('2026-07-10 10:10:00'), open: 100, high: 105, low: 98, close: 101) # before signal
      bar!(ts: Time.zone.parse('2026-07-10 10:15:00'), open: 110, high: 120, low: 108, close: 118) # entry
      bar!(ts: Time.zone.parse('2026-07-10 10:20:00'), open: 118, high: 130, low: 115, close: 121) # exit

      described_class.score!(candidate)
      candidate.reload

      expect(candidate.status).to eq('scored')
      expect(candidate.entry_price.to_f).to eq(110.0)
      expect(candidate.exit_price.to_f).to eq(121.0)
      expect(candidate.mfe_pct.to_f).to be_within(0.01).of(((130.0 - 110.0) / 110.0) * 100)
      expect(candidate.mae_pct.to_f).to be_within(0.01).of(((110.0 - 108.0) / 110.0) * 100)
      expect(candidate.return_pct.to_f).to be_within(0.01).of(((121.0 - 110.0) / 110.0) * 100)
      expect(candidate.holding_minutes).to eq(5)
    end

    it 'enters at the signal-candle close when entry_model is signal_candle_close' do
      candidate.update!(entry_model: 'signal_candle_close')
      bar!(ts: Time.zone.parse('2026-07-10 10:10:00'), open: 100, high: 106, low: 99, close: 104)
      bar!(ts: Time.zone.parse('2026-07-10 10:15:00'), open: 110, high: 120, low: 108, close: 118)

      described_class.score!(candidate)
      candidate.reload

      expect(candidate.entry_price.to_f).to eq(104.0)
    end

    it 'marks no_data (not entry-at-bar-0) when signal_candle_close has no bar at/before the signal timestamp' do
      candidate.update!(entry_model: 'signal_candle_close')
      bar!(ts: Time.zone.parse('2026-07-10 11:00:00'), open: 100, high: 106, low: 99, close: 104) # after signal only

      described_class.score!(candidate)
      candidate.reload

      expect(candidate.status).to eq('no_data')
      expect(candidate.entry_price).to be_nil
    end

    it 'marks the candidate failed (not silently no_data) when scoring raises' do
      bar!(ts: Time.zone.parse('2026-07-10 10:15:00'), open: 110, high: 120, low: 108, close: 118)
      allow(candidate).to receive(:bars).and_raise(ActiveRecord::StatementInvalid, 'boom')

      described_class.score!(candidate)
      candidate.reload

      expect(candidate.status).to eq('failed')
    end
  end
end
