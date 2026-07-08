# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Candles::BackfillJob do
  let!(:instrument) { create(:instrument, :nifty_index) }

  let(:dhan_response) do
    base = Time.zone.parse('2026-07-06 09:15:00')
    {
      'timestamp' => [base.to_i, (base + 1.minute).to_i],
      'open' => [25_000.0, 25_010.0],
      'high' => [25_020.0, 25_030.0],
      'low' => [24_990.0, 25_000.0],
      'close' => [25_010.0, 25_025.0],
      'volume' => [1_000, 1_100]
    }
  end

  before do
    allow_any_instance_of(Instrument).to receive(:intraday_ohlc).and_return(dhan_response) # rubocop:disable RSpec/AnyInstance
  end

  it 'enqueues Candles::PersistCandlesJob with the fetched candles' do
    expect(Candles::PersistCandlesJob).to receive(:perform_later).with(
      hash_including(instrument_key: 'NIFTY', security_id: '13', timeframe: '1m', source: 'backfill')
    ) do |args|
      expect(args[:candles].size).to eq(2)
      expect(args[:candles].first['close']).to eq(25_010.0)
    end

    described_class.perform_now(security_id: '13')
  end

  it 'does nothing when the instrument is not found' do
    expect(Candles::PersistCandlesJob).not_to receive(:perform_later)

    described_class.perform_now(security_id: 'unknown')
  end

  it 'does nothing when the DhanHQ response is empty' do
    allow_any_instance_of(Instrument).to receive(:intraday_ohlc).and_return({}) # rubocop:disable RSpec/AnyInstance
    expect(Candles::PersistCandlesJob).not_to receive(:perform_later)

    described_class.perform_now(security_id: '13')
  end
end
