# frozen_string_literal: true

require 'ruby_technical_analysis'
require 'technical_analysis'

module Indicators
  class HolyGrail < ApplicationService
    RTA = RubyTechnicalAnalysis
    TA  = TechnicalAnalysis

    EMA_FAST  = 34
    EMA_SLOW  = 100
    RSI_LEN   = 14
    ADX_LEN   = 14
    ATR_LEN   = 20
    MACD_F = 12
    MACD_S = 26
    MACD_SIG = 9

    DEFAULTS = {
      ema_fast: EMA_FAST,
      ema_slow: EMA_SLOW,
      rsi_len: RSI_LEN,
      adx_len: ADX_LEN,
      atr_len: ATR_LEN,
      macd_f: MACD_F,
      macd_s: MACD_S,
      macd_sig: MACD_SIG,

      adx_gate: 20.0,
      rsi_up_min: 40.0,
      rsi_down_max: 60.0,

      min_candles: EMA_SLOW
    }.freeze

    def self.demo_config
      {
        adx_gate: 0.0,
        rsi_up_min: 0.0,
        rsi_down_max: 100.0,
        min_candles: 1
      }
    end

    Result = Struct.new(
      :bias, :adx, :momentum, :proceed?,
      :sma50, :ema200, :rsi14, :atr14, :macd, :trend,
      keyword_init: true
    ) do
      def to_h = members.zip(values).to_h
    end

    def initialize(candles:, config: {})
      @candles = candles

      @cfg = DEFAULTS.merge((config || {}).transform_keys(&:to_sym))

      min_needed = @cfg[:min_candles].to_i.positive? ? @cfg[:min_candles].to_i : DEFAULTS[:min_candles]
      raise ArgumentError, "need ≥ #{min_needed} candles" if closes.size < min_needed
    end

    def call
      ema_fast = @cfg[:ema_fast]
      ema_slow = @cfg[:ema_slow]
      rsi_len  = @cfg[:rsi_len]
      adx_len  = @cfg[:adx_len]
      atr_len  = @cfg[:atr_len]

      sma50  = sma(ema_fast)
      ema200 = ema(ema_slow)
      rsi14  = rsi(rsi_len)
      macd_h = macd_hash
      adx14  = adx(adx_len)
      atr14  = atr(atr_len)

      bias =
        if    sma50 > ema200 then :bullish
        elsif sma50 < ema200 then :bearish
        else
          :neutral
        end

      rsi_up_min   = @cfg[:rsi_up_min].to_f
      rsi_down_max = @cfg[:rsi_down_max].to_f

      momentum =
        if macd_h[:macd] > macd_h[:signal] && rsi14 >= rsi_up_min
          :up
        elsif macd_h[:macd] < macd_h[:signal] && rsi14 <= rsi_down_max
          :down
        else
          :flat
        end

      adx_gate = @cfg[:adx_gate].to_f

      proceed =
        case bias
        when :bullish
          passed = adx14 >= adx_gate && momentum == :up
          Rails.logger.debug { "[HolyGrail] Not proceeding (bullish): adx=#{adx14} gate=#{adx_gate}, momentum=#{momentum}" } unless passed
          passed
        when :bearish
          passed = adx14 >= adx_gate && momentum == :down
          Rails.logger.debug { "[HolyGrail] Not proceeding (bearish): adx=#{adx14} gate=#{adx_gate}, momentum=#{momentum}" } unless passed
          passed
        else
          Rails.logger.debug { "[HolyGrail] Not proceeding (#{bias}): neutral bias, adx=#{adx14}, momentum=#{momentum}, gate=#{adx_gate}" }
          false
        end

      latest_time = Time.zone.at(stamps.last)
      Rails.logger.debug { "[HolyGrail] (#{latest_time}) proceed?=#{proceed}" }

      trend =
        if ema200 < closes.last && sma50 > ema200 then :up
        elsif ema200 > closes.last && sma50 < ema200 then :down
        else
          :side
        end

      Result.new(
        bias:, adx: adx14, momentum:, proceed?: proceed,
        sma50:, ema200:, rsi14:, atr14:, macd: macd_h, trend:
      )
    end

    def analyze_volatility
      atr_len = @cfg[:atr_len]
      atr_value = atr(atr_len)

      # Calculate volatility percentile based on recent ATR values
      recent_atrs = []
      (1..20).each do |_i|
        recent_atrs << atr(atr_len)
      rescue StandardError
        # Skip if not enough data
      end

      volatility_percentile = if recent_atrs.any?
                                sorted_atrs = recent_atrs.sort
                                current_rank = sorted_atrs.index(atr_value) || 0
                                current_rank.to_f / (sorted_atrs.size - 1)
                              else
                                0.5
                              end

      # Determine volatility level
      level = case volatility_percentile
              when 0.0...0.3
                :low
              when 0.3...0.7
                :medium
              else
                :high
              end

      {
        level: level,
        atr_value: atr_value,
        volatility_percentile: volatility_percentile
      }
    end

    private

    def closes = @candles['close'].map(&:to_f)
    def highs  = @candles['high'].map(&:to_f)
    def lows   = @candles['low'].map(&:to_f)
    def stamps = @candles['timestamp'] || []

    def ohlc_rows
      @ohlc_rows ||= highs.each_index.map do |i|
        {
          date_time: Time.zone.at(stamps[i] || 0),
          high: highs[i],
          low: lows[i],
          close: closes[i]
        }
      end
    end

    # — ruby-technical-analysis —
    def sma(len) = closes.last(len).sum / len.to_f
    def ema(len) = RTA::MovingAverages.new(series: closes, period: len).ema
    def rsi(len) = RTA::RelativeStrengthIndex.new(series: closes, period: len).call

    def macd_hash
      m, s, h = RTA::Macd.new(series: closes,
                              fast_period: @cfg[:macd_f],
                              slow_period: @cfg[:macd_s],
                              signal_period: @cfg[:macd_sig]).call
      { macd: m, signal: s, hist: h }
    end

    # — technical_analysis gem —
    def atr(len)
      TA::Atr.calculate(ohlc_rows.last(len * 2), period: len).first.atr
    end

    def adx(len)
      TA::Adx.calculate(ohlc_rows.last(len * 2), period: len).first.adx
    end
  end
end
