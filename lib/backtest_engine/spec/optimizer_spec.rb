# frozen_string_literal: true

require "spec_helper"
require "time"

RSpec.describe BacktestEngine::Optimizer do
  def candle(ts, o, h, l, c)
    BacktestEngine::Market::Candle.new(
      timestamp: ts,
      open: o,
      high: h,
      low: l,
      close: c,
      volume: 1000
    )
  end

  def make_day(t0, option_closes, day_type: :normal)
    index_candles = option_closes.each_with_index.map do |_c, i|
      candle(t0 + i * 60, 100 + i, 102 + i, 99 + i, 101 + i)
    end
    option_data = {
      ["ATM", :call] => index_candles.each_with_index.map do |c, i|
        { timestamp: c.timestamp, close: option_closes[i].to_f, iv: 20 }
      end
    }
    {
      index_candles: index_candles,
      option_data: option_data,
      day_type: day_type
    }
  end

  let(:t1) { Time.parse("2025-01-02 12:00:00") }
  let(:day1) { make_day(t1, [80, 90, 100, 100]) }
  let(:day2) { make_day(t1 + 86_400, [85, 95, 105, 105]) }
  let(:days) { [day1, day2] }

  describe ".run" do
    it "runs a 2x2 param grid and returns results sorted by expectancy" do
      param_grid = [
        { day_type: :normal },
        { day_type: :expiry }
      ]

      results = described_class.run(
        days: days,
        strategy_class: BacktestEngine::Strategies::ExpiryTrendV1,
        param_grid: param_grid,
        starting_capital: 100_000,
        lot_size: 50
      )

      expect(results.size).to eq(2)
      results.each do |r|
        expect(r).to be_a(described_class::RunResult)
        expect(r.params).to be_a(Hash)
        expect(r.metrics).to be_a(BacktestEngine::Metrics)
        expect(r.analytics).to be_a(BacktestEngine::Analytics::TradeAnalytics)
        expect(r.analytics.to_h).to include(:expectancy, :profit_factor, :total_pnl, :by_session)
      end
      expect(results).to eq(results.sort_by { |r| -r.analytics.expectancy })
    end

    it "accepts objective: :total_pnl" do
      param_grid = [{ day_type: :normal }]

      results = described_class.run(
        days: days,
        strategy_class: BacktestEngine::Strategies::ExpiryTrendV1,
        param_grid: param_grid,
        starting_capital: 100_000,
        lot_size: 50,
        objective: :total_pnl
      )

      expect(results.size).to eq(1)
      expect(results.first.analytics).to respond_to(:total_pnl)
    end
  end
end
