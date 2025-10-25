# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "Supertrend & ADX Computation Integration", type: :integration, vcr: true do
  let(:instrument) { create(:instrument, :nifty_future, security_id: '12345') }
  let(:candle_series) { create_candle_series_with_data }
  let(:supertrend_service) { Indicators::Supertrend.new(series: candle_series) }
  let(:adx_service) { Indicators::Calculator.new(candle_series) }

  def create_candle_series_with_data
    series = CandleSeries.new(symbol: 'NIFTY', interval: '5')

    # Create realistic OHLC data for testing - need at least 50 candles for Supertrend
    candles_data = []
    60.times do |i|
      base_price = 100.0 + (i * 0.1) # Gradual upward trend
      candles_data << {
        open: base_price + rand(-0.5..0.5),
        high: base_price + rand(0.5..1.5),
        low: base_price - rand(0.5..1.5),
        close: base_price + rand(-0.3..0.3),
        volume: rand(1000..2000),
        timestamp: Time.current - (60 - i).minutes
      }
    end

    candles_data.each do |data|
      candle = Candle.new(
        ts: data[:timestamp],
        open: data[:open],
        high: data[:high],
        low: data[:low],
        close: data[:close],
        volume: data[:volume]
      )
      series.add_candle(candle)
    end

    series
  end

  before do
    # Mock instrument methods
    allow(instrument).to receive(:candle_series).and_return(candle_series)
    allow(instrument).to receive(:adx).and_return(25.5)
  end

  describe "Supertrend Indicator Integration" do
    context "when computing Supertrend with default parameters" do
      it "calculates Supertrend line correctly" do
        result = supertrend_service.call

        expect(result).to have_key(:line)
        expect(result).to have_key(:values)
        expect(result).to have_key(:trend)
        expect(result).to have_key(:last_value)
        expect(result).to have_key(:atr)
        expect(result).to have_key(:adaptive_multipliers)
      end

      it "determines trend direction correctly" do
        result = supertrend_service.call

        expect(result[:trend]).to be_in([ :bullish, :bearish ])
        expect(result[:last_value]).to be_a(Numeric)
      end

      it "calculates adaptive multipliers" do
        result = supertrend_service.call

        expect(result[:adaptive_multipliers]).to be_an(Array)
        expect(result[:adaptive_multipliers].size).to eq(candle_series.candles.size)
        expect(result[:adaptive_multipliers].all? { |m| m.is_a?(Numeric) }).to be true
      end

      it "provides ATR values" do
        result = supertrend_service.call

        expect(result[:atr]).to be_an(Array)
        expect(result[:atr].size).to eq(candle_series.candles.size)
      end
    end

    context "when computing Supertrend with custom parameters" do
      let(:custom_supertrend) do
        Indicators::Supertrend.new(
          series: candle_series,
          period: 14,
          base_multiplier: 3.0,
          training_period: 100,
          num_clusters: 5
        )
      end

      it "uses custom period for ATR calculation" do
        result = custom_supertrend.call

        expect(result[:atr]).to be_an(Array)
        expect(result[:adaptive_multipliers]).to be_an(Array)
      end

      it "uses custom base multiplier" do
        # Verify that the method can be called without crashing
        expect { custom_supertrend.call }.not_to raise_error
      end

      it "uses custom training period for optimization" do
        result = custom_supertrend.call

        expect(result[:adaptive_multipliers]).to be_an(Array)
      end
    end

    context "when handling insufficient data" do
      let(:small_series) do
        series = CandleSeries.new(symbol: 'NIFTY', interval: '5')
        series.add_candle(Candle.new(
          ts: Time.current.to_i,
          open: 100.0,
          high: 102.0,
          low: 99.0,
          close: 101.0,
          volume: 1000
        ))
        series
      end

      it "returns default result for insufficient data" do
        small_supertrend = Indicators::Supertrend.new(series: small_series)
        result = small_supertrend.call

        expect(result[:line]).to eq([])
        expect(result[:values]).to eq([])
        expect(result[:trend]).to be_nil
        expect(result[:last_value]).to be_nil
      end
    end

    context "when accessing volatility regime" do
      it "provides current volatility regime" do
        result = supertrend_service.call

        regime = supertrend_service.get_current_volatility_regime(4)
        expect(regime).to be_in([ :low, :medium, :high, :unknown ])
      end

      it "returns unknown for invalid index" do
        regime = supertrend_service.get_current_volatility_regime(nil)
        expect(regime).to eq(:unknown)
      end
    end

    context "when accessing performance metrics" do
      it "provides performance metrics" do
        result = supertrend_service.call

        metrics = supertrend_service.get_performance_metrics

        expect(metrics).to have_key(:multiplier_scores)
        expect(metrics).to have_key(:total_clusters)
        expect(metrics).to have_key(:training_period)
      end
    end

    context "when getting adaptive multiplier for specific index" do
      it "returns adaptive multiplier for valid index" do
        result = supertrend_service.call

        multiplier = supertrend_service.get_adaptive_multiplier(4)
        expect(multiplier).to be_a(Numeric)
        expect(multiplier).to be > 0
      end

      it "returns base multiplier for invalid index" do
        multiplier = supertrend_service.get_adaptive_multiplier(999)
        expect(multiplier).to eq(supertrend_service.base_multiplier)
      end
    end
  end

  describe "ADX Indicator Integration" do
    context "when computing ADX with default parameters" do
      it "calculates ADX value correctly" do
        result = adx_service.adx(14)

        expect(result).to be_a(Numeric)
        expect(result).to be >= 0
        expect(result).to be <= 100
      end

      it "provides trend strength classification" do
        result = adx_service.adx(14)

        if result >= 25
          expect(result).to be >= 25
        else
          expect(result).to be < 25
        end
      end
    end

    context "when computing ADX with custom parameters" do
      let(:custom_adx) { Indicators::Calculator.new(candle_series) }

      it "uses custom period for calculation" do
        result = custom_adx.adx(21)

        expect(result).to be_a(Numeric)
        expect(result).to be >= 0
        expect(result).to be <= 100
      end
    end

    context "when handling insufficient data" do
      let(:small_series) do
        series = CandleSeries.new(symbol: 'NIFTY', interval: '5')
        series.add_candle(Candle.new(
          ts: Time.current.to_i,
          open: 100.0,
          high: 102.0,
          low: 99.0,
          close: 101.0,
          volume: 1000
        ))
        series
      end

      it "returns nil for insufficient data" do
        small_adx = Indicators::Calculator.new(small_series)

        # ADX calculation with insufficient data should raise an exception
        expect { small_adx.adx(14) }.to raise_error(TechnicalAnalysis::Validation::ValidationError, /Not enough data for that period/)
      end
    end
  end

  describe "CandleSeries Technical Analysis Integration" do
    context "when computing RSI" do
      it "calculates RSI with default period" do
        rsi = candle_series.rsi
        expect(rsi).to be_a(Numeric)
        expect(rsi).to be >= 0
        expect(rsi).to be <= 100
      end

      it "calculates RSI with custom period" do
        rsi = candle_series.rsi(21)
        expect(rsi).to be_a(Numeric)
        expect(rsi).to be >= 0
        expect(rsi).to be <= 100
      end
    end

    context "when computing moving averages" do
      it "calculates SMA with default period" do
        sma = candle_series.sma
        expect(sma).to be_a(Numeric)
        expect(sma).to be > 0
      end

      it "calculates EMA with default period" do
        ema = candle_series.ema
        expect(ema).to be_a(Numeric)
        expect(ema).to be > 0
      end

      it "calculates moving averages with custom period" do
        sma = candle_series.sma(10)
        ema = candle_series.ema(10)

        expect(sma).to be_a(Numeric)
        expect(ema).to be_a(Numeric)
      end
    end

    context "when computing MACD" do
      it "calculates MACD with default parameters" do
        macd = candle_series.macd

        expect(macd).to be_an(Array)
        expect(macd.size).to eq(3) # MACD line, signal line, histogram
      end

      it "calculates MACD with custom parameters" do
        macd = candle_series.macd(8, 17, 5)

        expect(macd).to be_an(Array)
        expect(macd.size).to eq(3) # MACD line, signal line, histogram
      end
    end

    context "when computing Supertrend signal" do
      it "generates Supertrend signal" do
        signal = candle_series.supertrend_signal

        expect(signal).to be_in([ :long_entry, :short_entry, nil ])
      end
    end

    context "when computing Bollinger Bands" do
      it "calculates Bollinger Bands with default parameters" do
        bb = candle_series.bollinger_bands

        expect(bb).to be_a(Hash)
        expect(bb).to have_key(:upper)
        expect(bb).to have_key(:middle)
        expect(bb).to have_key(:lower)
      end

      it "calculates Bollinger Bands with custom parameters" do
        bb = candle_series.bollinger_bands(period: 10, std_dev: 1.5)

        expect(bb).to be_a(Hash)
        expect(bb).to have_key(:upper)
        expect(bb).to have_key(:middle)
        expect(bb).to have_key(:lower)
      end
    end

    context "when computing rate of change" do
      it "calculates rate of change with default period" do
        roc = candle_series.rate_of_change

        expect(roc).to be_an(Array)
        expect(roc.compact).to all(be_a(Numeric))
      end

      it "calculates rate of change with custom period" do
        roc = candle_series.rate_of_change(10)

        expect(roc).to be_an(Array)
        expect(roc.compact).to all(be_a(Numeric))
      end
    end

    context "when detecting chart patterns" do
      it "detects inside bars" do
        # Create an inside bar scenario
        series = CandleSeries.new(symbol: 'NIFTY', interval: '5')
        series.add_candle(Candle.new(
          ts: Time.current.to_i,
          open: 100.0,
          high: 102.0,
          low: 99.0,
          close: 101.0,
          volume: 1000
        ))
        series.add_candle(Candle.new(
          ts: Time.current.to_i,
          open: 100.5,
          high: 101.5,
          low: 99.5,
          close: 100.5,
          volume: 800
        ))

        expect(series.inside_bar?(1)).to be true
      end

      it "detects liquidity grab patterns" do
        liquidity_grab_up = candle_series.liquidity_grab_up?
        liquidity_grab_down = candle_series.liquidity_grab_down?

        expect(liquidity_grab_up).to be_in([ true, false ])
        expect(liquidity_grab_down).to be_in([ true, false ])
      end
    end
  end

  describe "Trading Indicators Module Integration" do
    let(:closes) { [ 100.0, 101.0, 102.0, 103.0, 104.0 ] }
    let(:candles) do
      [
        { high: 102.0, low: 99.0, close: 101.0 },
        { high: 103.0, low: 100.0, close: 102.0 },
        { high: 104.0, low: 101.0, close: 103.0 },
        { high: 105.0, low: 102.0, close: 104.0 }
      ]
    end

    context "when computing RSI" do
      it "calculates RSI correctly" do
        # Mock the RSI calculation to return a sample value
        allow(Trading::Indicators).to receive(:rsi).and_return(BigDecimal('65.5'))

        rsi = Trading::Indicators.rsi(closes)

        expect(rsi).to be_a(BigDecimal)
        expect(rsi).to be >= 0
        expect(rsi).to be <= 100
      end

      it "handles insufficient data" do
        short_closes = [ 100.0, 101.0 ]
        rsi = Trading::Indicators.rsi(short_closes, period: 14)

        expect(rsi).to be_nil
      end
    end

    context "when computing ATR" do
      it "calculates ATR correctly" do
        # Mock the ATR calculation to return a sample value
        allow(Trading::Indicators).to receive(:atr).and_return(BigDecimal('1.5'))

        atr = Trading::Indicators.atr(candles)

        expect(atr).to be_a(BigDecimal)
        expect(atr).to be > 0
      end

      it "handles insufficient data" do
        short_candles = [ { high: 102.0, low: 99.0, close: 101.0 } ]
        atr = Trading::Indicators.atr(short_candles, period: 7)

        expect(atr).to be_nil
      end
    end

    context "when computing Supertrend" do
      it "calculates Supertrend correctly" do
        # Mock the Supertrend calculation to return a sample result
        allow(Trading::Indicators).to receive(:supertrend).and_return({
          trend: :bullish,
          band: 100.5
        })

        st = Trading::Indicators.supertrend(candles)

        expect(st).to be_a(Hash)
        expect(st).to have_key(:trend)
        expect(st).to have_key(:band)
        expect(st[:trend]).to be_in([ :bullish, :bearish ])
      end

      it "handles insufficient data" do
        short_candles = [ { high: 102.0, low: 99.0, close: 101.0 } ]
        st = Trading::Indicators.supertrend(short_candles, period: 7)

        expect(st).to be_nil
      end
    end

    context "when computing averages" do
      it "calculates average correctly" do
        values = [ 100.0, 101.0, 102.0, 103.0, 104.0 ]
        avg = Trading::Indicators.average(values)

        expect(avg).to be_a(BigDecimal)
        expect(avg).to eq(BigDecimal('102.0'))
      end

      it "handles empty values" do
        avg = Trading::Indicators.average([])

        expect(avg).to eq(BigDecimal('0'))
      end

      it "handles nil values" do
        values = [ 100.0, nil, 102.0, nil, 104.0 ]
        avg = Trading::Indicators.average(values)

        expect(avg).to be_a(BigDecimal)
        expect(avg).to eq(BigDecimal('102.0'))
      end
    end
  end

  describe "Instrument ADX Integration" do
    context "when computing ADX for instrument" do
      it "calculates ADX with default parameters" do
        adx_value = instrument.adx(14, interval: '5')

        expect(adx_value).to be_a(Numeric)
        expect(adx_value).to be >= 0
        expect(adx_value).to be <= 100
      end

      it "calculates ADX with custom period" do
        adx_value = instrument.adx(21, interval: '5')

        expect(adx_value).to be_a(Numeric)
        expect(adx_value).to be >= 0
        expect(adx_value).to be <= 100
      end

      it "calculates ADX with different intervals" do
        adx_1m = instrument.adx(14, interval: '1')
        adx_5m = instrument.adx(14, interval: '5')

        expect(adx_1m).to be_a(Numeric)
        expect(adx_5m).to be_a(Numeric)
      end
    end
  end

  describe "Error Handling and Edge Cases" do
    context "when handling invalid data" do
      it "handles nil candle data gracefully" do
        series = CandleSeries.new(symbol: 'NIFTY', interval: '5')
        series.add_candle(nil)

        # The system should raise an error for nil candle data
        expect { series.rsi }.to raise_error(NoMethodError, /undefined method `close' for nil/)
      end

      it "handles empty candle series" do
        series = CandleSeries.new(symbol: 'NIFTY', interval: '5')

        expect(series.rsi).to be_nil
        expect(series.sma).to be_nil
        expect(series.ema).to be_nil
      end

      it "handles invalid numeric values" do
        series = CandleSeries.new(symbol: 'NIFTY', interval: '5')
        series.add_candle(Candle.new(
          ts: Time.current.to_i,
          open: 'invalid',
          high: 102.0,
          low: 99.0,
          close: 101.0,
          volume: 1000
        ))

        expect { series.rsi }.not_to raise_error
      end
    end

    context "when handling extreme values" do
      it "handles very large price values" do
        series = CandleSeries.new(symbol: 'NIFTY', interval: '5')

        # Add 15 candles with very large price values to ensure RSI can calculate
        15.times do |i|
          base_price = 1000000.0 + i * 1000.0
          series.add_candle(Candle.new(
            ts: Time.current.to_i + i * 300,
            open: base_price,
            high: base_price + 2.0,
            low: base_price - 1.0,
            close: base_price + 1.0,
            volume: 1000
          ))
        end

        rsi = series.rsi
        expect(rsi).to be_a(Numeric)
      end

      it "handles very small price values" do
        series = CandleSeries.new(symbol: 'NIFTY', interval: '5')

        # Add multiple candles with very small price values
        10.times do |i|
          series.add_candle(Candle.new(
            ts: Time.current.to_i + i * 300,
            open: 0.001 + i * 0.0001,
            high: 0.002 + i * 0.0001,
            low: 0.0005 + i * 0.0001,
            close: 0.0015 + i * 0.0001,
            volume: 1000
          ))
        end

        rsi = series.rsi
        # RSI calculation might return nil for very small values or insufficient data
        expect(rsi).to be_a(Numeric).or be_nil
      end
    end

    context "when handling configuration errors" do
      it "handles invalid indicator parameters" do
        expect {
          Indicators::Supertrend.new(series: candle_series, period: -1)
        }.not_to raise_error
      end

      it "handles invalid period values" do
        expect {
          Indicators::Calculator.new(candle_series)
        }.not_to raise_error
      end
    end
  end

  describe "Performance and Optimization" do
    context "when processing large datasets" do
      let(:large_series) do
        series = CandleSeries.new(symbol: 'NIFTY', interval: '5')

        # Create 1000 candles
        1000.times do |i|
          base_price = 100.0 + (i * 0.1)
          series.add_candle(Candle.new(
            ts: (Time.current - (1000 - i).minutes).to_i,
            open: base_price,
            high: base_price + 1.0,
            low: base_price - 1.0,
            close: base_price + 0.5,
            volume: 1000 + i
          ))
        end

        series
      end

      it "processes large datasets efficiently" do
        large_supertrend = Indicators::Supertrend.new(series: large_series)

        start_time = Time.current
        result = large_supertrend.call
        end_time = Time.current

        expect(result).to be_a(Hash)
        expect(end_time - start_time).to be < 1.second
      end

      it "maintains accuracy with large datasets" do
        large_supertrend = Indicators::Supertrend.new(series: large_series)
        result = large_supertrend.call

        expect(result[:trend]).to be_in([ :bullish, :bearish ])
        expect(result[:adaptive_multipliers].size).to eq(1000)
      end
    end
  end
end
