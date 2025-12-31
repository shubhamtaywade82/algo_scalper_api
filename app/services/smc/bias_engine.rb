# frozen_string_literal: true

module Smc
  class BiasEngine
    HTF_INTERVAL = '60'
    MTF_INTERVAL = '15'
    LTF_INTERVAL = '5'

    HTF_CANDLES = 60
    MTF_CANDLES = 100
    LTF_CANDLES = 150

    def initialize(instrument)
      @instrument = instrument
    end

    def decision
      htf = context_for(interval: HTF_INTERVAL, max_candles: HTF_CANDLES)
      mtf = context_for(interval: MTF_INTERVAL, max_candles: MTF_CANDLES)
      ltf = context_for(interval: LTF_INTERVAL, max_candles: LTF_CANDLES)

      return :no_trade unless htf_bias_valid?(htf)
      return :no_trade unless mtf_aligns?(htf, mtf)

      ltf_entry(htf, mtf, ltf)
    end

    private

    def context_for(interval:, max_candles:)
      series = @instrument&.candles(interval: interval)
      trimmed = trim_series(series, max_candles: max_candles)
      Smc::Context.new(trimmed)
    end

    def trim_series(series, max_candles:)
      return series unless series&.respond_to?(:candles)

      candles = series.candles.last(max_candles)
      return series if candles.size == series.candles.size

      CandleSeries.new(symbol: series.symbol, interval: series.interval).tap do |s|
        candles.each { |c| s.add_candle(c) }
      end
    rescue StandardError => e
      Rails.logger.error("[Smc::BiasEngine] #{e.class} - #{e.message}")
      series
    end

    def htf_bias_valid?(ctx)
      ctx.pd.discount? || ctx.pd.premium?
    end

    def mtf_aligns?(htf, mtf)
      htf.structure.trend == mtf.structure.trend || mtf.structure.choch?
    end

    def ltf_entry(htf, _mtf, ltf)
      avrz = Avrz::Detector.new(@instrument.candles(interval: LTF_INTERVAL))
      return :no_trade unless avrz.rejection?

      if htf.pd.discount? && ltf.liquidity.sell_side_taken? && ltf.structure.choch?
        :call
      elsif htf.pd.premium? && ltf.liquidity.buy_side_taken? && ltf.structure.choch?
        :put
      else
        :no_trade
      end
    end
  end
end

