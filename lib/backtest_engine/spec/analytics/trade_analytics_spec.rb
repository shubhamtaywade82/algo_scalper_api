# frozen_string_literal: true

require "spec_helper"
require "time"

RSpec.describe BacktestEngine::Analytics::TradeAnalytics do
  let(:trade_struct) { BacktestEngine::Metrics::Trade }

  def make_trade(pnl:, session: :s2, regime: :trend_bull, day_type: :normal)
    trade_struct.new(
      entry_time: Time.parse("2025-01-02 10:00:00"),
      exit_time: Time.parse("2025-01-02 10:30:00"),
      side: :buy,
      option_type: :call,
      strike: "ATM",
      entry_price: 100.0,
      exit_price: 100.0 + pnl,
      pnl: pnl,
      pnl_pct: pnl,
      day_type: day_type,
      session: session,
      regime: regime
    )
  end

  describe ".from_metrics" do
    it "builds analytics from Metrics" do
      metrics = BacktestEngine::Metrics.new
      metrics.record_trade(make_trade(pnl: 10.0))
      metrics.record_trade(make_trade(pnl: -5.0))
      metrics.record_trade(make_trade(pnl: 20.0))

      analytics = described_class.from_metrics(metrics)

      expect(analytics.total_pnl).to eq(25.0)
      expect(analytics.total_trades).to eq(3)
      expect(analytics.win_rate).to be_within(0.01).of(2.0 / 3.0 * 100)
      expect(analytics.expectancy).to be_within(0.01).of(25.0 / 3.0)
      expect(analytics.profit_factor).to eq(30.0 / 5.0)
    end

    it "computes max_drawdown from equity_curve when provided" do
      metrics = BacktestEngine::Metrics.new
      metrics.record_trade(make_trade(pnl: 100.0))
      metrics.record_trade(make_trade(pnl: -60.0))

      analytics = described_class.from_metrics(
        metrics,
        equity_curve: [100_000.0, 100_100.0, 100_040.0]
      )

      expected_dd = (100_100.0 - 100_040.0) / 100_100.0
      expect(analytics.max_drawdown).to be_within(0.0001).of(expected_dd)
    end

    it "computes max_drawdown from running PnL when no equity_curve" do
      metrics = BacktestEngine::Metrics.new
      metrics.record_trade(make_trade(pnl: 50.0))
      metrics.record_trade(make_trade(pnl: -80.0))
      metrics.record_trade(make_trade(pnl: 30.0))

      analytics = described_class.from_metrics(metrics)

      expect(analytics.max_drawdown).to be > 0
    end
  end

  describe "breakdown by session and regime" do
    it "returns by_session with pnl and count" do
      metrics = BacktestEngine::Metrics.new
      metrics.record_trade(make_trade(pnl: 10.0, session: :s2))
      metrics.record_trade(make_trade(pnl: -5.0, session: :s2))
      metrics.record_trade(make_trade(pnl: 20.0, session: :s4))

      analytics = described_class.from_metrics(metrics)

      expect(analytics.by_session[:s2]).to eq({ pnl: 5.0, count: 2 })
      expect(analytics.by_session[:s4]).to eq({ pnl: 20.0, count: 1 })
    end

    it "returns by_regime with pnl and count" do
      metrics = BacktestEngine::Metrics.new
      metrics.record_trade(make_trade(pnl: 15.0, regime: :trend_bull))
      metrics.record_trade(make_trade(pnl: -10.0, regime: :trend_bear))

      analytics = described_class.from_metrics(metrics)

      expect(analytics.by_regime[:trend_bull]).to eq({ pnl: 15.0, count: 1 })
      expect(analytics.by_regime[:trend_bear]).to eq({ pnl: -10.0, count: 1 })
    end

    it "returns by_day_type with pnl and count" do
      metrics = BacktestEngine::Metrics.new
      metrics.record_trade(make_trade(pnl: 10.0, day_type: :normal))
      metrics.record_trade(make_trade(pnl: 20.0, day_type: :expiry))

      analytics = described_class.from_metrics(metrics)

      expect(analytics.by_day_type[:normal]).to eq({ pnl: 10.0, count: 1 })
      expect(analytics.by_day_type[:expiry]).to eq({ pnl: 20.0, count: 1 })
    end
  end

  describe ".from_results" do
    it "merges multiple results and builds analytics" do
      m1 = BacktestEngine::Metrics.new
      m1.record_trade(make_trade(pnl: 10.0))
      p1 = BacktestEngine::Portfolio::Portfolio.new(starting_capital: 100_000)
      r1 = BacktestEngine::BacktestSession::Result.new(portfolio: p1, metrics: m1)

      m2 = BacktestEngine::Metrics.new
      m2.record_trade(make_trade(pnl: 20.0))
      p2 = BacktestEngine::Portfolio::Portfolio.new(starting_capital: 100_000)
      r2 = BacktestEngine::BacktestSession::Result.new(portfolio: p2, metrics: m2)

      analytics = described_class.from_results([r1, r2])

      expect(analytics.total_trades).to eq(2)
      expect(analytics.total_pnl).to eq(30.0)
    end
  end

  describe ".from_result" do
    it "builds analytics from BacktestSession::Result" do
      metrics = BacktestEngine::Metrics.new
      metrics.record_trade(make_trade(pnl: 100.0))
      portfolio = BacktestEngine::Portfolio::Portfolio.new(starting_capital: 100_000)
      portfolio.record_equity(pnl: 100.0)
      result = BacktestEngine::BacktestSession::Result.new(portfolio: portfolio, metrics: metrics)

      analytics = described_class.from_result(result)

      expect(analytics.total_pnl).to eq(100.0)
      expect(analytics.total_trades).to eq(1)
    end
  end

  describe "#to_h and #summary" do
    it "returns hash with all keys" do
      metrics = BacktestEngine::Metrics.new
      metrics.record_trade(make_trade(pnl: 5.0))
      analytics = described_class.from_metrics(metrics)

      h = analytics.to_h
      expect(h).to include(:total_pnl, :total_trades, :win_rate, :avg_win, :avg_loss,
                           :expectancy, :profit_factor, :max_drawdown,
                           :by_session, :by_regime, :by_day_type)
    end

    it "summary returns a string" do
      metrics = BacktestEngine::Metrics.new
      metrics.record_trade(make_trade(pnl: 5.0))
      analytics = described_class.from_metrics(metrics)

      expect(analytics.summary).to be_a(String)
      expect(analytics.summary).to include("Total PnL")
      expect(analytics.summary).to include("Trades")
    end
  end

  describe "profit_factor edge cases" do
    it "returns Infinity when no losses" do
      metrics = BacktestEngine::Metrics.new
      metrics.record_trade(make_trade(pnl: 10.0))
      metrics.record_trade(make_trade(pnl: 20.0))

      analytics = described_class.from_metrics(metrics)

      expect(analytics.profit_factor).to eq(Float::INFINITY)
    end

    it "returns 0 when no profits" do
      metrics = BacktestEngine::Metrics.new
      metrics.record_trade(make_trade(pnl: -10.0))
      metrics.record_trade(make_trade(pnl: -20.0))

      analytics = described_class.from_metrics(metrics)

      expect(analytics.profit_factor).to eq(0.0)
    end
  end
end
