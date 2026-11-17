# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Live::CandlePollerService, :freeze_time do
  subject(:service) { described_class.new }

  let(:now) { Time.zone.local(2026, 11, 17, 22, 16) }
  let(:instrument) { create(:instrument, symbol_name: 'NIFTY', security_id: '13', segment: 'index', exchange: 'nse') }

  before do
    travel_to(now)
    allow(IndexConfigLoader).to receive(:load_indices).and_return([{ key: 'NIFTY' }])
    allow(IndexInstrumentCache.instance).to receive(:get_or_fetch).and_return(instrument)
  end

  def store_bar(at)
    Candles::Record.create!(instrument_key: 'NIFTY', exchange_segment: 'IDX_I', security_id: '13', timeframe: '1m',
                            ts: at, open: 100, high: 101, low: 99, close: 100)
  end

  describe 'warmup backfill' do
    it 'fetches only from just before the last stored bar instead of re-fetching days of stored history' do
      store_bar(Time.zone.local(2026, 11, 17, 15, 29))

      expect { service.send(:enqueue_warmup_backfill) }.to have_enqueued_job(Candles::BackfillJob)
        .with(security_id: '13', from_date: '2026-11-17 15:14:00', to_date: '2026-11-17 22:16:00')
    end

    it 'uses the default lookback for an index that has no stored candles yet' do
      expect { service.send(:enqueue_warmup_backfill) }.to have_enqueued_job(Candles::BackfillJob)
        .with(security_id: '13', to_date: '2026-11-17 22:16:00')
    end

    it 'never reaches back further than the default lookback after a long outage' do
      store_bar(Time.zone.local(2026, 10, 1, 15, 29))

      expect { service.send(:enqueue_warmup_backfill) }.to have_enqueued_job(Candles::BackfillJob)
        .with(security_id: '13', from_date: '2026-11-12 22:16:00', to_date: '2026-11-17 22:16:00')
    end
  end
end
