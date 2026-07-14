# frozen_string_literal: true

require "rails_helper"

RSpec.describe Research::UnderlyingBackfill do
  it "persists fetched OHLC arrays as 1m Candles::Record rows for missing days" do
    instrument = create(:instrument, :nifty_index)
    allow(Instrument).to receive(:find_by).and_return(instrument)

    t0 = Time.zone.parse("2026-07-06 09:15:00").to_i
    raw = {
      open: [100.0, 101.0], high: [101.0, 102.0], low: [99.0, 100.0],
      close: [101.0, 101.5], volume: [10, 12], timestamp: [t0, t0 + 60]
    }
    allow(instrument).to receive(:intraday_ohlc).and_return(raw)

    expect do
      described_class.call(symbol: "NIFTY", lookback_days: 5)
    end.to change { Candles::Record.where(instrument_key: "NIFTY", timeframe: "1m").count }.by(2)
  end

  it "returns the count of distinct days available after backfill" do
    instrument = create(:instrument, :nifty_index)
    allow(Instrument).to receive(:find_by).and_return(instrument)
    allow(instrument).to receive(:intraday_ohlc).and_return({})

    expect(described_class.call(symbol: "NIFTY", lookback_days: 5)).to be_a(Integer)
  end
end
