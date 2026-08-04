# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Candles::PersistCandlesJob do
  let(:candles) do
    [
      { "timestamp" => "2026-07-06T09:15:00.000Z", "open" => 25_000.0, "high" => 25_050.0,
        "low" => 24_980.0, "close" => 25_020.0, "volume" => 1_000, "oi" => 0 },
      { "timestamp" => "2026-07-06T09:16:00.000Z", "open" => 25_020.0, "high" => 25_060.0,
        "low" => 25_000.0, "close" => 25_040.0, "volume" => 1_200, "oi" => 0 }
    ]
  end

  def perform
    described_class.perform_now(
      instrument_key: "NIFTY",
      exchange_segment: "IDX_I",
      security_id: "13",
      timeframe: "1m",
      source: "live",
      candles: candles
    )
  end

  it "creates one Candles::Record per candle" do
    expect { perform }.to change(Candles::Record, :count).by(2)
  end

  it "stores OHLCV values correctly" do
    perform
    record = Candles::Record.for_instrument("NIFTY").order(:ts).first
    expect(record).to have_attributes(
      exchange_segment: "IDX_I",
      security_id: "13",
      timeframe: "1m",
      source: "live",
      open: 25_000.0,
      high: 25_050.0,
      low: 24_980.0,
      close: 25_020.0,
      volume: 1_000
    )
  end

  it "upserts idempotently on repeat calls with the same timestamps" do
    perform
    perform
    expect(Candles::Record.for_instrument("NIFTY").count).to eq(2)
  end

  it "overwrites values when the same bar is re-persisted with different data (backfill reconciling live)" do
    perform
    described_class.perform_now(
      instrument_key: "NIFTY",
      exchange_segment: "IDX_I",
      security_id: "13",
      timeframe: "1m",
      source: "backfill",
      candles: [candles.first.merge("close" => 25_099.0)]
    )

    record = Candles::Record.for_instrument("NIFTY").order(:ts).first
    expect(record.close).to eq(25_099.0)
    expect(record.source).to eq("backfill")
  end

  it "does nothing when candles is blank" do
    expect do
      described_class.perform_now(
        instrument_key: "NIFTY", exchange_segment: "IDX_I", security_id: "13",
        timeframe: "1m", source: "live", candles: []
      )
    end.not_to change(Candles::Record, :count)
  end
end
