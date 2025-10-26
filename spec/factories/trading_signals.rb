# frozen_string_literal: true

FactoryBot.define do
  factory :trading_signal do
    index_key { 'nifty' }
    direction { TradingSignal::DIRECTIONS[:bullish] }
    timeframe { '1m' }
    supertrend_value { BigDecimal('25000.00') }
    adx_value { BigDecimal('25.5') }
    candle_timestamp { 1.hour.ago }
    signal_timestamp { Time.current }
    confidence_score { 0.75 }
    metadata { { 'source' => 'supertrend_adx', 'version' => '1.0' } }

    trait :bullish do
      direction { TradingSignal::DIRECTIONS[:bullish] }
      supertrend_value { BigDecimal('25000.00') }
      adx_value { BigDecimal('30.0') }
      confidence_score { 0.8 }
    end

    trait :bearish do
      direction { TradingSignal::DIRECTIONS[:bearish] }
      supertrend_value { BigDecimal('24800.00') }
      adx_value { BigDecimal('28.0') }
      confidence_score { 0.7 }
    end

    trait :avoid do
      direction { TradingSignal::DIRECTIONS[:avoid] }
      supertrend_value { BigDecimal('25000.00') }
      adx_value { BigDecimal('15.0') }
      confidence_score { 0.3 }
    end

    trait :high_confidence do
      confidence_score { 0.9 }
    end

    trait :low_confidence do
      confidence_score { 0.4 }
    end

    trait :nifty_signal do
      index_key { 'nifty' }
      supertrend_value { BigDecimal('25000.00') }
    end

    trait :banknifty_signal do
      index_key { 'banknifty' }
      supertrend_value { BigDecimal('56000.00') }
    end

    trait :sensex_signal do
      index_key { 'sensex' }
      supertrend_value { BigDecimal('82000.00') }
    end

    trait :one_minute do
      timeframe { '1m' }
    end

    trait :five_minute do
      timeframe { '5m' }
    end

    trait :fifteen_minute do
      timeframe { '15m' }
    end

    trait :one_hour do
      timeframe { '1h' }
    end

    trait :daily do
      timeframe { '1d' }
    end

    trait :recent do
      signal_timestamp { 1.hour.ago }
      candle_timestamp { 2.hours.ago }
    end

    trait :old do
      signal_timestamp { 2.days.ago }
      candle_timestamp { 2.days.ago }
    end

    trait :with_metadata do
      metadata do
        {
          'source' => 'supertrend_adx',
          'version' => '1.0',
          'indicators' => {
            'supertrend' => {
              'value' => supertrend_value.to_f,
              'multiplier' => 2.0,
              'period' => 10
            },
            'adx' => {
              'value' => adx_value.to_f,
              'period' => 14
            }
          },
          'market_conditions' => {
            'volatility' => 'normal',
            'trend_strength' => 'strong'
          }
        }
      end
    end

    trait :nifty_bullish_1m do
      nifty_signal
      bullish
      one_minute
      recent
    end

    trait :banknifty_bearish_5m do
      banknifty_signal
      bearish
      five_minute
      recent
    end

    trait :sensex_avoid_daily do
      sensex_signal
      avoid
      daily
      low_confidence
    end
  end
end
