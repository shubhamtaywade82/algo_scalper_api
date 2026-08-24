# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DataQuality::DailyCheckJob do
  def candle_row(instrument_key:, timeframe:, ts:)
    Candles::Record.create!(
      instrument_key: instrument_key, exchange_segment: 'NSE_FNO', security_id: '99999',
      timeframe: timeframe, ts: ts, open: 100, high: 101, low: 99, close: 100.5
    )
  end

  before do
    allow(AlgoConfig).to receive(:fetch).and_return(indices: [{ key: 'NIFTY' }])
  end

  context 'when today is not a trading day' do
    it 'does not create a metric row' do
      allow(Market::Calendar).to receive(:trading_day?).and_return(false)

      expect { described_class.new.perform }.not_to change(DataQualityDailyMetric, :count)
    end
  end

  context 'when today is a trading day' do
    before { allow(Market::Calendar).to receive(:trading_day?).and_return(true) }

    it 'creates one metric row for today' do
      expect { described_class.new.perform }.to change(DataQualityDailyMetric, :count).by(1)

      expect(DataQualityDailyMetric.last.trading_date).to eq(Date.current)
    end

    it 'counts aligned candles and reports 100% alignment when every row lands on the timeframe boundary' do
      base = Date.current.in_time_zone('Asia/Kolkata').change(hour: 9, min: 15)
      candle_row(instrument_key: 'IDX_NIFTY', timeframe: '5m', ts: base)
      candle_row(instrument_key: 'IDX_NIFTY', timeframe: '5m', ts: base + 5.minutes)

      described_class.new.perform

      metric = DataQualityDailyMetric.last
      expect(metric.candle_alignment_accuracy_pct).to eq(100.0)
      expect(metric.meta['per_symbol_candle_gaps']['IDX_NIFTY']['actual']).to eq(2)
    end

    it 'flags a misaligned candle (not on the timeframe boundary) as reducing alignment accuracy' do
      base = Date.current.in_time_zone('Asia/Kolkata').change(hour: 9, min: 15)
      candle_row(instrument_key: 'IDX_NIFTY', timeframe: '5m', ts: base) # aligned
      candle_row(instrument_key: 'IDX_NIFTY', timeframe: '5m', ts: base + 2.minutes) # misaligned

      described_class.new.perform

      expect(DataQualityDailyMetric.last.candle_alignment_accuracy_pct).to eq(50.0)
    end

    it 'reports a positive missing_candle_count when far fewer candles exist than the trading-window expects' do
      base = Date.current.in_time_zone('Asia/Kolkata').change(hour: 9, min: 15)
      candle_row(instrument_key: 'IDX_NIFTY', timeframe: '5m', ts: base)

      described_class.new.perform

      # 375 minutes / 5m interval = 75 expected candles, only 1 present
      expect(DataQualityDailyMetric.last.missing_candle_count).to eq(74)
    end

    it 'leaves alignment/candle fields nil when no candles exist today at all, without raising' do
      expect { described_class.new.perform }.not_to raise_error

      metric = DataQualityDailyMetric.last
      expect(metric.missing_candle_count).to eq(0)
      expect(metric.candle_alignment_accuracy_pct).to be_nil
    end

    it 'reports 100% instrument mapping accuracy when all traded-symbol rows have a security_id' do
      instrument = create(:instrument, symbol_name: 'NIFTY')
      create(:derivative, instrument: instrument, underlying_symbol: 'NIFTY')

      described_class.new.perform

      expect(DataQualityDailyMetric.last.instrument_mapping_accuracy_pct).to eq(100.0)
    end

    it 'creates an AuditLog entry and records the count when expired derivatives exist for a traded symbol' do
      instrument = create(:instrument, symbol_name: 'NIFTY')
      create(:derivative, instrument: instrument, underlying_symbol: 'NIFTY', expiry_date: 1.day.ago)
      create(:derivative, instrument: instrument, underlying_symbol: 'NIFTY', expiry_date: 1.month.from_now)

      expect { described_class.new.perform }.to change(AuditLog, :count).by(1)

      expect(DataQualityDailyMetric.last.expired_instrument_count).to eq(1)
      log = AuditLog.last
      expect(log.event_type).to eq('reconciliation_mismatch')
      expect(log.metadata['count']).to eq(1)
    end

    it 'does not create an AuditLog entry when no expired derivatives exist' do
      instrument = create(:instrument, symbol_name: 'NIFTY')
      create(:derivative, instrument: instrument, underlying_symbol: 'NIFTY', expiry_date: 1.month.from_now)

      expect { described_class.new.perform }.not_to change(AuditLog, :count)
    end

    it 'does not mutate any Instrument/Derivative rows (observability only, no auto-remediation)' do
      instrument = create(:instrument, symbol_name: 'NIFTY')
      expired = create(:derivative, instrument: instrument, underlying_symbol: 'NIFTY', expiry_date: 1.day.ago)

      described_class.new.perform

      expect(expired.reload.attributes).to eq(expired.attributes)
    end

    describe 'fill-price reconciliation' do
      def stub_candles(low:, high:, at:)
        allow(DhanHQ::Models::HistoricalData).to receive(:intraday).and_return([
                                                                                 { timestamp: at.change(sec: 0), open: low, high: high, low: low, close: high, volume: 100 }
                                                                               ])
      end

      before { allow(Notifications::TelegramNotifier.instance).to receive(:notify_warning) }

      it 'reports zero checked when there are no exited positions today' do
        described_class.new.perform

        metric = DataQualityDailyMetric.last
        expect(metric.fill_reconciliation_checked_count).to eq(0)
        expect(metric.fill_reconciliation_mismatch_count).to eq(0)
      end

      it 'does not flag a fill whose entry/exit price falls inside the real candle range' do
        at = Time.zone.now.change(sec: 0)
        create(:position_tracker, :exited, security_id: '45104', segment: 'NSE_FNO',
                                           entry_price: 50.0, exit_price: 51.0, created_at: at, exited_at: at + 1.minute)
        stub_candles(low: 49.0, high: 52.0, at: at)

        described_class.new.perform

        metric = DataQualityDailyMetric.last
        expect(metric.fill_reconciliation_checked_count).to eq(1)
        expect(metric.fill_reconciliation_mismatch_count).to eq(0)
        expect(AuditLog.where(event_type: 'reconciliation_mismatch').count).to eq(0)
        expect(Notifications::TelegramNotifier.instance).not_to have_received(:notify_warning)
      end

      it 'flags and audits a fill price that does not match the real candle range' do
        at = Time.zone.now.change(sec: 0)
        create(:position_tracker, :exited, security_id: '45104', segment: 'NSE_FNO',
                                           entry_price: 275.75, exit_price: 145.5, created_at: at, exited_at: at)
        stub_candles(low: 143.45, high: 145.75, at: at)

        described_class.new.perform

        metric = DataQualityDailyMetric.last
        expect(metric.fill_reconciliation_mismatch_count).to eq(1)
        expect(metric.meta['fill_mismatches'].first['field']).to eq('entry_price')

        log = AuditLog.where(event_type: 'reconciliation_mismatch').last
        expect(log.metadata['kind']).to eq('fill_price_vs_ohlc_mismatch')
        expect(log.metadata['count']).to eq(1)
        expect(Notifications::TelegramNotifier.instance).to have_received(:notify_warning)
      end

      it 'does not raise when the candle fetch fails for a security' do
        create(:position_tracker, :exited, security_id: '45104', segment: 'NSE_FNO',
                                           entry_price: 50.0, exit_price: 51.0, created_at: Time.zone.now, exited_at: Time.zone.now)
        allow(DhanHQ::Models::HistoricalData).to receive(:intraday).and_raise(StandardError, 'boom')

        expect { described_class.new.perform }.not_to raise_error
        expect(DataQualityDailyMetric.last.fill_reconciliation_mismatch_count).to eq(0)
      end
    end

    it 'reads and clears the tick staleness sampler counters into a rate' do
      real_cache = ActiveSupport::Cache::MemoryStore.new
      allow(Rails).to receive(:cache).and_return(real_cache)
      keys = DataQuality::TickStalenessSamplerJob.cache_keys_for(Date.current)
      real_cache.write(keys[:total], 10)
      real_cache.write(keys[:stale], 3)

      described_class.new.perform

      expect(DataQualityDailyMetric.last.tick_staleness_rate_pct).to eq(30.0)
      expect(real_cache.read(keys[:total])).to be_nil
      expect(real_cache.read(keys[:stale])).to be_nil
    end
  end
end
