# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Research::RegimeSignalGenerator do
  describe '.run' do
    before do
      allow(Market::Calendar).to receive(:trading_day?).and_return(true)
    end

    def stub_snapshot(regime_overrides = {}, close: 25_000.0)
      regime = {
        "market_structure" => "range", "recent_bos" => false, "recent_choch" => false,
        "trend" => "neutral", "volatility_regime" => "stable", "momentum" => "neutral_momentum",
        "volume_regime" => "average", "time_context" => "morning", "vwap_relation" => "at_vwap",
        "liquidity_sweep" => "none", "opening_range_breakout" => "inside_range", "gap" => "none"
      }.merge(regime_overrides)

      allow(Research::UnderlyingContextSnapshot).to receive(:at)
        .and_return({ "close" => close, "regime" => regime })
    end

    it 'creates a bullish signal when trend is trending and volatility is expanding' do
      stub_snapshot({ "trend" => "strong_bullish", "volatility_regime" => "expanding" })

      signals = described_class.run(symbol: "NIFTY", from_date: "2026-07-13", to_date: "2026-07-13",
                                    checkpoint_times: ["09:45"])

      expect(signals.size).to eq(1)
      expect(signals.first.direction).to eq("bullish")
      expect(signals.first.strategy_name).to eq("regime_scan")
      expect(signals.first.spot_price.to_f).to eq(25_000.0)
      expect(signals.first.metadata["regime"]["trend"]).to eq("strong_bullish")
    end

    it 'creates a bearish signal when trend is trending bearish and volatility is expanding' do
      stub_snapshot({ "trend" => "weak_bearish", "volatility_regime" => "expanding" })

      signals = described_class.run(symbol: "NIFTY", from_date: "2026-07-13", to_date: "2026-07-13",
                                    checkpoint_times: ["09:45"])

      expect(signals.first.direction).to eq("bearish")
    end

    it 'does not signal on a trending regime without volatility expansion' do
      stub_snapshot({ "trend" => "strong_bullish", "volatility_regime" => "stable" })

      signals = described_class.run(symbol: "NIFTY", from_date: "2026-07-13", to_date: "2026-07-13",
                                    checkpoint_times: ["09:45"])

      expect(signals).to be_empty
    end

    it 'creates a bullish signal on a neutral (ranging) trend with a sell-side liquidity sweep' do
      stub_snapshot({ "trend" => "neutral", "liquidity_sweep" => "sell_side_sweep" })

      signals = described_class.run(symbol: "NIFTY", from_date: "2026-07-13", to_date: "2026-07-13",
                                    checkpoint_times: ["09:45"])

      expect(signals.first.direction).to eq("bullish")
    end

    it 'creates a bearish signal on a neutral (ranging) trend with a buy-side liquidity sweep' do
      stub_snapshot({ "trend" => "neutral", "liquidity_sweep" => "buy_side_sweep" })

      signals = described_class.run(symbol: "NIFTY", from_date: "2026-07-13", to_date: "2026-07-13",
                                    checkpoint_times: ["09:45"])

      expect(signals.first.direction).to eq("bearish")
    end

    it 'does not signal on a neutral trend with no liquidity sweep' do
      stub_snapshot({ "trend" => "neutral", "liquidity_sweep" => "none" })

      signals = described_class.run(symbol: "NIFTY", from_date: "2026-07-13", to_date: "2026-07-13",
                                    checkpoint_times: ["09:45"])

      expect(signals).to be_empty
    end

    it 'skips checkpoints with an empty snapshot (insufficient candle history)' do
      allow(Research::UnderlyingContextSnapshot).to receive(:at).and_return({})

      signals = described_class.run(symbol: "NIFTY", from_date: "2026-07-13", to_date: "2026-07-13",
                                    checkpoint_times: ["09:45"])

      expect(signals).to be_empty
    end

    it 'skips non-trading days' do
      allow(Market::Calendar).to receive(:trading_day?).and_return(false)
      stub_snapshot({ "trend" => "strong_bullish", "volatility_regime" => "expanding" })

      signals = described_class.run(symbol: "NIFTY", from_date: "2026-07-13", to_date: "2026-07-13",
                                    checkpoint_times: ["09:45"])

      expect(signals).to be_empty
    end

    it 'is idempotent across repeated runs for the same symbol/date/checkpoint' do
      stub_snapshot({ "trend" => "strong_bullish", "volatility_regime" => "expanding" })

      first_run = described_class.run(symbol: "NIFTY", from_date: "2026-07-13", to_date: "2026-07-13",
                                      checkpoint_times: ["09:45"])
      second_run = described_class.run(symbol: "NIFTY", from_date: "2026-07-13", to_date: "2026-07-13",
                                       checkpoint_times: ["09:45"])

      expect(first_run.map(&:id)).to eq(second_run.map(&:id))
      expect(Research::Signal.where(strategy_name: "regime_scan").count).to eq(1)
    end

    it 'does not raise and continues when one checkpoint fails' do
      call_count = 0
      allow(Research::UnderlyingContextSnapshot).to receive(:at) do
        call_count += 1
        raise "boom" if call_count == 1

        { "close" => 25_000.0, "regime" => { "trend" => "strong_bullish", "volatility_regime" => "expanding" } }
      end

      signals = described_class.run(symbol: "NIFTY", from_date: "2026-07-13", to_date: "2026-07-13",
                                    checkpoint_times: ["09:45", "11:30"])

      expect(signals.size).to eq(1)
    end
  end
end
