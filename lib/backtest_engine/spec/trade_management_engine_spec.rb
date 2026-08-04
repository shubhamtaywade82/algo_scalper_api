# frozen_string_literal: true

require "spec_helper"
require "time"

RSpec.describe BacktestEngine::TradeManagementEngine do
  let(:t0) { Time.parse("2026-07-09 09:15:00") }
  let(:index_candles) do
    [
      BacktestEngine::Market::Candle.new(timestamp: t0, open: 24000, high: 24010, low: 23990, close: 24000, volume: 1000),
      BacktestEngine::Market::Candle.new(timestamp: t0 + 60, open: 24000, high: 24050, low: 24000, close: 24040, volume: 1000),
      BacktestEngine::Market::Candle.new(timestamp: t0 + 120, open: 24040, high: 24080, low: 24030, close: 24070, volume: 1000),
      BacktestEngine::Market::Candle.new(timestamp: t0 + 180, open: 24070, high: 24070, low: 23980, close: 23990, volume: 1000)
    ]
  end

  let(:indicator_series) { BacktestEngine::Market::CandleSeries.new(index_candles) }
  let(:execution_engine) { BacktestEngine::ExecutionEngine.new(lot_size: 50, slippage_pct: 0.0) }

  let(:position) do
    {
      entry_price: 100.0,
      entry_time: t0,
      option_type: :call,
      strike: "ATM",
      sl_pct: 20.0,
      target_pct: 50.0
    }
  end

  let(:option_data) do
    {
      ["ATM", :call] => [
        { timestamp: t0, open: 100, high: 100, low: 100, close: 100, volume: 100 },
        { timestamp: t0 + 60, open: 100, high: 120, low: 95, close: 110, volume: 100 },
        { timestamp: t0 + 120, open: 110, high: 140, low: 105, close: 130, volume: 100 },
        { timestamp: t0 + 180, open: 130, high: 130, low: 75, close: 78, volume: 100 }
      ]
    }
  end

  subject(:tme) do
    described_class.new(
      position,
      indicator_series: indicator_series,
      option_data: option_data,
      execution_engine: execution_engine
    )
  end

  describe "#evaluate" do
    it "handles basic hard stop loss" do
      result = tme.evaluate(0, index_candles[0], 100.0, t0)
      expect(result).to be_nil

      result2 = tme.evaluate(3, index_candles[3], 78.0, t0 + 180)
      expect(result2).to be_a(Hash)
      expect(result2[:action]).to eq(:exit)
      expect(result2[:reason]).to eq("HARD_STOP_LOSS")
    end

    it "handles target hit" do
      result = tme.evaluate(0, index_candles[0], 100.0, t0)
      expect(result).to be_nil

      result2 = tme.evaluate(2, index_candles[2], 152.0, t0 + 120)
      expect(result2).to be_a(Hash)
      expect(result2[:action]).to eq(:exit)
      expect(result2[:reason]).to eq("TARGET_HIT")
    end

    context "with breakeven trigger" do
      before { position[:breakeven_trigger] = 15.0 }

      it "moves stop loss to breakeven once triggered" do
        tme.evaluate(0, index_candles[0], 100.0, t0)
        tme.evaluate(1, index_candles[1], 110.0, t0 + 60)
        
        expect(tme.evaluate(1, index_candles[1], 90.0, t0 + 60)).to be_nil

        tme.evaluate(1, index_candles[1], 120.0, t0 + 60)

        result = tme.evaluate(2, index_candles[2], 95.0, t0 + 120)
        expect(result).to be_a(Hash)
        expect(result[:action]).to eq(:exit)
        expect(result[:reason]).to eq("TRAILING_STOP_LOSS")
        expect(result[:price]).to eq(100.0)
      end
    end

    context "with fixed_pct trailing stop-loss" do
      before do
        position[:trail] = true
        position[:trail_trigger] = 10.0
        position[:trail_type] = :fixed_pct
        position[:trail_value] = 10.0
      end

      it "trails stop-loss dynamically" do
        tme.evaluate(0, index_candles[0], 100.0, t0)
        
        tme.evaluate(1, index_candles[1], 120.0, t0 + 60)
        expect(tme.trailing_sl).to eq(108.0)

        tme.evaluate(2, index_candles[2], 130.0, t0 + 120)
        expect(tme.trailing_sl).to eq(117.0)

        result = tme.evaluate(3, index_candles[3], 115.0, t0 + 180)
        expect(result).to be_a(Hash)
        expect(result[:action]).to eq(:exit)
        expect(result[:reason]).to eq("TRAILING_STOP_LOSS")
        expect(result[:price]).to eq(117.0)
      end
    end

    context "with time stop" do
      before { position[:max_hold_minutes] = 2 }

      it "exits position after time limit is exceeded" do
        tme.evaluate(0, index_candles[0], 100.0, t0)
        tme.evaluate(1, index_candles[1], 110.0, t0 + 60)

        result = tme.evaluate(2, index_candles[2], 112.0, t0 + 120)
        expect(result).to be_a(Hash)
        expect(result[:action]).to eq(:exit)
        expect(result[:reason]).to eq("TIME_STOP")
      end
    end

    context "with underlying trend exit" do
      before { position[:underlying_trend_exit] = true }

      it "exits if index candle closes below EMA 20" do
        tme.evaluate(0, index_candles[0], 100.0, t0)
        
        result = tme.evaluate(3, index_candles[3], 105.0, t0 + 180)
        expect(result).to be_a(Hash)
        expect(result[:action]).to eq(:exit)
        expect(result[:reason]).to eq("UNDERLYING_REGIME_FLIP")
      end
    end
  end

  describe "#exit_metrics" do
    it "correctly computes MFE, MAE and Exit Efficiency" do
      tme.evaluate(0, index_candles[0], 100.0, t0)
      tme.evaluate(1, index_candles[1], 120.0, t0 + 60)
      tme.evaluate(2, index_candles[2], 90.0, t0 + 120)
      tme.evaluate(3, index_candles[3], 130.0, t0 + 180)

      metrics = tme.exit_metrics(115.0)
      expect(metrics[:mfe]).to eq(130.0)
      expect(metrics[:mae]).to eq(90.0)
      expect(metrics[:exit_efficiency]).to eq(50.0)
    end
  end
end
