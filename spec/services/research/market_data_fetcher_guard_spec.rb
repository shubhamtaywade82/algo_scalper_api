# frozen_string_literal: true

require "rails_helper"

RSpec.describe Research::MarketDataFetcher do
  describe "strict mode" do
    it "raises SyntheticDataError instead of generating a synthetic underlying dataset" do
      allow(Candles::Record).to receive(:where).and_return(Candles::Record.none)
      allow(File).to receive(:exist?).with("today_market_data.json").and_return(false)

      expect do
        described_class.run(symbol: "NO_SUCH_SYMBOL", lookback_days: 5, strict: true)
      end.to raise_error(Research::MarketDataFetcher::SyntheticDataError)
    end

    it "returns [] from load_or_simulate_options instead of simulating premiums" do
      nifty_candles = [{ timestamp: Time.zone.now, open: 25_000.0, high: 25_010.0,
                         low: 24_990.0, close: 25_005.0, volume: 100 }]
      allow(Research::OptionBar).to receive(:where).and_return(Research::OptionBar.none)
      allow(Research::OptionCandleFetcher).to receive(:call).and_return([])

      result = described_class.load_or_simulate_options(
        "NIFTY", "CE", 25_000, Time.zone.today, nifty_candles, strike_label: "ATM", strict: true
      )
      expect(result).to eq([])
    end
  end
end
