# frozen_string_literal: true

require "rails_helper"

RSpec.describe Research::UnderlyingBackfill do
  it "persists fetched OHLC arrays as 1m Candles::Record rows for missing days" do
    create(:instrument, :nifty_index)

    t0 = Time.zone.parse("2026-07-06 09:15:00").to_i
    raw = {
      open: [100.0, 101.0], high: [101.0, 102.0], low: [99.0, 100.0],
      close: [101.0, 101.5], volume: [10, 12], timestamp: [t0, t0 + 60]
    }
    allow_any_instance_of(Instrument).to receive(:intraday_ohlc).and_return(raw) # rubocop:disable RSpec/AnyInstance

    expect do
      described_class.call(symbol: "NIFTY", lookback_days: 5)
    end.to change { Candles::Record.where(instrument_key: "NIFTY", timeframe: "1m").count }.by(2)
  end

  it "returns the count of distinct days available after backfill" do
    create(:instrument, :nifty_index)
    allow_any_instance_of(Instrument).to receive(:intraday_ohlc).and_return({}) # rubocop:disable RSpec/AnyInstance

    expect(described_class.call(symbol: "NIFTY", lookback_days: 5)).to be_a(Integer)
  end

  it "resolves SENSEX via its actual exchange (BSE), not a hardcoded NSE lookup" do
    # SENSEX's Instrument row lives on BSE. A backfill that hardcodes exchange: "nse"
    # would silently no-op for SENSEX (find_by returns nil, method just returns the
    # existing count) instead of raising or backfilling anything.
    create(:instrument, :sensex_index)

    t0 = Time.zone.parse("2026-07-06 09:15:00").to_i
    raw = {
      open: [80_000.0], high: [80_100.0], low: [79_900.0],
      close: [80_050.0], volume: [0], timestamp: [t0]
    }
    allow_any_instance_of(Instrument).to receive(:intraday_ohlc).and_return(raw) # rubocop:disable RSpec/AnyInstance

    expect do
      described_class.call(symbol: "SENSEX", lookback_days: 5)
    end.to change { Candles::Record.where(instrument_key: "SENSEX", timeframe: "1m").count }.by(1)
  end
end
