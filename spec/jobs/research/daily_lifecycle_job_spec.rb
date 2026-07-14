# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Research::DailyLifecycleJob do
  let(:job) { described_class.new }
  let(:session_date) { Date.parse('2026-07-10') }

  before do
    allow(Market::Calendar).to receive(:trading_days_ago).with(1).and_return(session_date)
    allow(Market::Calendar).to receive(:trading_day?).with(session_date).and_return(true)
  end

  describe '#perform' do
    it 'resolves spot from the first persisted candle at/after 09:15 and runs the lifecycle board' do
      Candles::Record.create!(
        instrument_key: 'NIFTY', exchange_segment: 'NSE_IDX', security_id: '13', timeframe: '1m',
        ts: Time.zone.parse('2026-07-10 09:15:00'), open: 24_800.0, high: 24_820, low: 24_790, close: 24_810,
        volume: 1000, source: 'live'
      )
      allow(Research::LifecycleRunner).to receive(:run)

      job.perform('NIFTY')

      expect(Research::LifecycleRunner).to have_received(:run).with(
        symbol: 'NIFTY', spot: 24_800.0, expiry_flag: 'WEEK',
        entry_ts: Time.zone.parse('2026-07-10 09:15:00'),
        from_date: '2026-07-10', to_date: '2026-07-11', max_distance: 5
      )
    end

    it 'uses MONTH as the expiry flag for BANKNIFTY' do
      Candles::Record.create!(
        instrument_key: 'BANKNIFTY', exchange_segment: 'NSE_IDX', security_id: '25', timeframe: '1m',
        ts: Time.zone.parse('2026-07-10 09:15:00'), open: 51_000.0, high: 51_100, low: 50_900, close: 51_050,
        volume: 1000, source: 'live'
      )
      allow(Research::LifecycleRunner).to receive(:run)

      job.perform('BANKNIFTY')

      expect(Research::LifecycleRunner).to have_received(:run).with(hash_including(expiry_flag: 'MONTH'))
    end

    it 'skips without raising when the day is not a trading day' do
      allow(Market::Calendar).to receive(:trading_day?).with(session_date).and_return(false)
      allow(Research::LifecycleRunner).to receive(:run)

      job.perform('NIFTY')

      expect(Research::LifecycleRunner).not_to have_received(:run)
    end

    it 'skips without raising when no candle data has been persisted yet' do
      allow(Research::LifecycleRunner).to receive(:run)

      job.perform('NIFTY')

      expect(Research::LifecycleRunner).not_to have_received(:run)
    end

    it 'notifies on failure instead of raising' do
      Candles::Record.create!(
        instrument_key: 'NIFTY', exchange_segment: 'NSE_IDX', security_id: '13', timeframe: '1m',
        ts: Time.zone.parse('2026-07-10 09:15:00'), open: 24_800.0, high: 24_820, low: 24_790, close: 24_810,
        volume: 1000, source: 'live'
      )
      allow(Research::LifecycleRunner).to receive(:run).and_raise(StandardError, 'boom')
      notifier = instance_double(Notifications::TelegramNotifier, notify_error: true)
      allow(Notifications::TelegramNotifier).to receive(:instance).and_return(notifier)

      expect { job.perform('NIFTY') }.not_to raise_error
      expect(notifier).to have_received(:notify_error)
    end
  end
end
