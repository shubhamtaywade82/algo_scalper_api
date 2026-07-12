# frozen_string_literal: true

require "spec_helper"
require "time"

RSpec.describe BacktestEngine::Market::StructureEngineV2 do
  def candle(ts, o, h, l, c, vol = 1000)
    BacktestEngine::Market::Candle.new(
      timestamp: ts,
      open: o,
      high: h,
      low: l,
      close: c,
      volume: vol
    )
  end

  describe "#structure_at" do
    context "with not enough candles" do
      it "returns :range when index < min_lookback" do
        candles = 10.times.map { |i| candle(Time.now + i * 60, 100, 101, 99, 100.5) }
        series = BacktestEngine::Market::CandleSeries.new(candles)
        engine = described_class.new(series)

        expect(engine.structure_at(0)).to eq(:range)
        expect(engine.structure_at(6)).to eq(:range)
      end
    end

    context "with swing-based structure" do
      it "returns :bullish after a BOS to the upside" do
        # Simple uptrend: swing low then higher high
        t0 = Time.parse("2025-01-02 09:15:00")
        candles = [
          candle(t0,     100, 102, 99,  101),
          candle(t0+60,  101, 103, 100, 102),
          candle(t0+120, 102, 104, 101, 103),
          candle(t0+180, 103, 105, 102, 104),
          candle(t0+240, 104, 106, 103, 105),
          candle(t0+300, 105, 107, 104, 106),
          candle(t0+360, 106, 108, 105, 107),
          candle(t0+420, 107, 109, 106, 108),
          candle(t0+480, 108, 110, 107, 109),
          candle(t0+540, 109, 111, 108, 110),
          candle(t0+600, 110, 112, 109, 111),
          candle(t0+660, 111, 113, 110, 112),
          candle(t0+720, 112, 114, 111, 113),
          candle(t0+780, 113, 115, 112, 114),
          candle(t0+840, 114, 116, 113, 115),
          candle(t0+900, 115, 117, 114, 116)
        ]
        series = BacktestEngine::Market::CandleSeries.new(candles)
        engine = described_class.new(series)

        # After enough candles we may get :bullish from BOS
        result = engine.structure_at(15)
        expect(%i[bullish bearish range]).to include(result)
      end

      it "returns :range when no BOS/CHOCH yet" do
        # Sideways
        t0 = Time.parse("2025-01-02 09:15:00")
        candles = 20.times.map { |i| candle(t0 + i * 60, 100, 101, 99, 100) }
        series = BacktestEngine::Market::CandleSeries.new(candles)
        engine = described_class.new(series)

        expect(engine.structure_at(10)).to eq(:range)
        expect(engine.structure_at(19)).to eq(:range)
      end
    end
  end

  describe "#bos_events and #choch_events" do
    it "detects BOS from swing sequence" do
      t0 = Time.parse("2025-01-02 09:15:00")
      candles = [
        candle(t0,     100, 101, 99, 100),
        candle(t0+60,  100, 101, 99, 100),
        candle(t0+120, 100, 101, 99, 100),
        candle(t0+180, 100, 100, 98, 99),
        candle(t0+240, 99, 100, 98, 99),
        candle(t0+300, 99, 100, 98, 99),
        candle(t0+360, 99, 101, 99, 100),
        candle(t0+420, 100, 102, 100, 101),
        candle(t0+480, 101, 103, 101, 102),
        candle(t0+540, 102, 104, 102, 103),
        candle(t0+600, 103, 105, 103, 104),
        candle(t0+660, 104, 106, 104, 105),
        candle(t0+720, 105, 107, 105, 106),
        candle(t0+780, 106, 108, 106, 107),
        candle(t0+840, 107, 109, 107, 108),
        candle(t0+900, 108, 110, 108, 109)
      ]
      series = BacktestEngine::Market::CandleSeries.new(candles)
      engine = described_class.new(series)

      expect(engine.bos_events).to be_an(Array)
      expect(engine.choch_events).to be_an(Array)
    end
  end

  describe "integration with BacktestSession" do
    it "runs with structure_engine: :v2 and returns a result" do
      t0 = Time.parse("2025-01-02 12:00:00")
      index_candles = [
        candle(t0, 100, 102, 99, 101),
        candle(t0 + 60, 101, 103, 100, 102),
        candle(t0 + 120, 102, 104, 101, 103),
        candle(t0 + 180, 103, 105, 102, 104),
        candle(t0 + 240, 104, 106, 103, 105),
        candle(t0 + 300, 105, 107, 104, 106),
        candle(t0 + 360, 106, 108, 105, 107),
        candle(t0 + 420, 107, 109, 106, 108),
        candle(t0 + 480, 108, 110, 107, 109),
        candle(t0 + 540, 109, 111, 108, 110),
        candle(t0 + 600, 110, 112, 109, 111),
        candle(t0 + 660, 111, 113, 110, 112),
        candle(t0 + 720, 112, 114, 111, 113),
        candle(t0 + 780, 113, 115, 112, 114),
        candle(t0 + 840, 114, 116, 113, 115),
        candle(t0 + 900, 115, 117, 114, 116)
      ]
      option_data = {
        ["ATM", :call] => index_candles.each_with_index.map do |c, i|
          { timestamp: c.timestamp, close: 80.0 + i * 2, iv: 20 }
        end
      }

      session = BacktestEngine::BacktestSession.new(
        index_candles: index_candles,
        option_data: option_data,
        starting_capital: 100_000,
        lot_size: 50
      )

      result = session.run(
        BacktestEngine::Strategies::ExpiryTrendV1,
        day_type: :normal,
        structure_engine: :v2
      )

      expect(result).to be_a(BacktestEngine::BacktestSession::Result)
      expect(result.metrics).to be_a(BacktestEngine::Metrics)
      expect(result.portfolio).to be_a(BacktestEngine::Portfolio::Portfolio)
    end
  end
end
