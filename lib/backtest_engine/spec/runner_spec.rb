require "spec_helper"

RSpec.describe BacktestEngine::Runner do
  it "runs a simple backtest and returns metrics" do
    index_candles = [
      BacktestEngine::Market::Candle.new(
        timestamp: Time.at(1),
        open: 100,
        high: 101,
        low: 99,
        close: 100,
        volume: 10
      ),
      BacktestEngine::Market::Candle.new(
        timestamp: Time.at(2),
        open: 101,
        high: 103,
        low: 100,
        close: 102,
        volume: 12
      )
    ]

    option_data = {
      call: {
        100 => [
          { timestamp: 1, open: 10, high: 11, low: 9, close: 10 },
          { timestamp: 2, open: 11, high: 13, low: 10, close: 12 }
        ]
      },
      put: {}
    }

    runner = described_class.new(
      index_candles: index_candles,
      option_data: option_data,
      lot_size: 50
    )

    metrics = runner.run

    expect(metrics).to be_a(BacktestEngine::Metrics)
    expect(metrics.total_pnl).to be_a(Numeric)
  end
end

