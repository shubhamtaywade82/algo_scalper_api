# frozen_string_literal: true

require "spec_helper"
require "time"

RSpec.describe BacktestEngine::BacktestSession do
  def candle(ts, close: 100.0)
    BacktestEngine::Market::Candle.new(
      timestamp: ts,
      open: close,
      high: close,
      low: close,
      close: close,
      volume: 1000
    )
  end

  class BuyOnBullish
    def initialize(context:)
      @context = context
    end

    def call
      return { action: :skip, reason: "not bullish" } unless @context[:structure] == :bullish

      {
        action: :buy,
        option_type: :call,
        strike: :atm,
        sl_pct: 30,
        target_pct: 60,
        trail: true,
        trail_trigger: 40,
        max_hold_minutes: 25
      }
    end
  end

  describe "#run" do
    context "when strategy_router is enabled" do
      it "does not overwrite skip reasons from the strategy" do
        strategy_class = Class.new do
          def initialize(context:)
            @context = context
          end

          def call
            { action: :skip, reason: "Outside time window" }
          end
        end

        index_candles = [
          candle(Time.parse("2025-01-02 09:15:00")),
          candle(Time.parse("2025-01-02 12:00:00"))
        ]

        session = described_class.new(
          index_candles: index_candles,
          option_data: {},
          starting_capital: 100_000,
          lot_size: 50
        )

        result = session.run(
          strategy_class,
          day_type: :expiry,
          strategy_router: true,
          structure_engine: :v2,
          regime_scorer: true
        )

        expect(result.metrics.trades.size).to eq(0)
        expect(result.metrics.skip_reasons["Outside time window"]).to eq(2)
      end
    end

    let(:t0) { Time.parse("2025-01-02 12:00:00") }
    let(:index_candles) do
      [
        BacktestEngine::Market::Candle.new(timestamp: t0, open: 100, high: 102, low: 99, close: 101, volume: 1000),
        BacktestEngine::Market::Candle.new(timestamp: t0 + 60, open: 101, high: 103, low: 100, close: 102, volume: 1000),
        BacktestEngine::Market::Candle.new(timestamp: t0 + 120, open: 102, high: 104, low: 101, close: 103, volume: 1000),
        BacktestEngine::Market::Candle.new(timestamp: t0 + 180, open: 103, high: 105, low: 102, close: 104, volume: 1000)
      ]
    end

    let(:option_data) do
      {
        ["ATM", :call] => [
          { timestamp: t0, close: 80, iv: 20 },
          { timestamp: t0 + 60, close: 90, iv: 20 },
          { timestamp: t0 + 120, close: 100, iv: 20 },
          { timestamp: t0 + 180, close: 180, iv: 20 }
        ]
      }
    end

    it "replays sequentially and records a tagged trade" do
      session = described_class.new(
        index_candles: index_candles,
        option_data: option_data,
        starting_capital: 100_000,
        lot_size: 50
      )

      result = session.run(BuyOnBullish, day_type: :normal)

      expect(result.metrics.trades.size).to eq(1)

      trade = result.metrics.trades.first
      expect(trade.pnl).to be > 0
      expect(trade.day_type).to eq(:normal)
      expect(trade.session).to eq(:s3)
      expect(trade.regime).to eq(:trend_bull)
    end
  end
end
