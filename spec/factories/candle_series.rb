# frozen_string_literal: true

FactoryBot.define do
  factory :candle_series do
    skip_create # CandleSeries is a PORO, not an ActiveRecord model
    initialize_with { new(symbol: symbol, interval: interval) }

    symbol { 'NIFTY' }
    interval { '5' }

    trait :nifty_series do
      symbol { 'NIFTY' }
      interval { '5' }
    end

    trait :banknifty_series do
      symbol { 'BANKNIFTY' }
      interval { '5' }
    end

    trait :sensex_series do
      symbol { 'SENSEX' }
      interval { '5' }
    end

    trait :one_minute do
      interval { '1' }
    end

    trait :five_minute do
      interval { '5' }
    end

    trait :fifteen_minute do
      interval { '15' }
    end

    trait :one_hour do
      interval { '60' }
    end

    trait :daily do
      interval { '1d' }
    end

    trait :with_candles do
      after(:build) do |series|
        # Add 20 candles to the series
        20.times do |i|
          candle = build(:candle,
                         timestamp: Time.current - (20 - i).hours,
                         open: 25_000.0 + (i * 10),
                         high: 25_050.0 + (i * 10),
                         low: 24_950.0 + (i * 10),
                         close: 25_025.0 + (i * 10),
                         volume: 1_000_000 + (i * 10_000))
          series.add_candle(candle)
        end
      end
    end

    trait :bullish_trend do
      after(:build) do |series|
        # Add candles with upward trend
        10.times do |i|
          base_price = 25_000.0 + (i * 50)
          candle = build(:candle,
                         timestamp: Time.current - (10 - i).hours,
                         open: base_price,
                         high: base_price + 30,
                         low: base_price - 20,
                         close: base_price + 25,
                         volume: 1_000_000)
          series.add_candle(candle)
        end
      end
    end

    trait :bearish_trend do
      after(:build) do |series|
        # Add candles with downward trend
        10.times do |i|
          base_price = 25_000.0 - (i * 50)
          candle = build(:candle,
                         timestamp: Time.current - (10 - i).hours,
                         open: base_price,
                         high: base_price + 20,
                         low: base_price - 30,
                         close: base_price - 25,
                         volume: 1_000_000)
          series.add_candle(candle)
        end
      end
    end

    trait :sideways_trend do
      after(:build) do |series|
        # Add candles with sideways movement
        10.times do |i|
          base_price = 25_000.0 + (i.even? ? 20 : -20)
          candle = build(:candle,
                         timestamp: Time.current - (10 - i).hours,
                         open: base_price,
                         high: base_price + 15,
                         low: base_price - 15,
                         close: base_price + (i.even? ? 10 : -10),
                         volume: 1_000_000)
          series.add_candle(candle)
        end
      end
    end

    trait :high_volatility do
      after(:build) do |series|
        # Add candles with high volatility
        10.times do |i|
          base_price = 25_000.0 + ((rand - 0.5) * 200)
          candle = build(:candle,
                         timestamp: Time.current - (10 - i).hours,
                         open: base_price,
                         high: base_price + rand(50..100),
                         low: base_price - rand(50..100),
                         close: base_price + ((rand - 0.5) * 100),
                         volume: rand(2_000_000..5_000_000))
          series.add_candle(candle)
        end
      end
    end

    trait :low_volatility do
      after(:build) do |series|
        # Add candles with low volatility
        10.times do |i|
          base_price = 25_000.0 + ((rand - 0.5) * 20)
          candle = build(:candle,
                         timestamp: Time.current - (10 - i).hours,
                         open: base_price,
                         high: base_price + rand(5..15),
                         low: base_price - rand(5..15),
                         close: base_price + ((rand - 0.5) * 10),
                         volume: rand(500_000..1_000_000))
          series.add_candle(candle)
        end
      end
    end

    trait :with_gaps do
      after(:build) do |series|
        # Add candles with gaps
        5.times do |i|
          base_price = 25_000.0 + (i * 100)
          candle = build(:candle,
                         timestamp: Time.current - (5 - i).hours,
                         open: base_price,
                         high: base_price + 30,
                         low: base_price - 20,
                         close: base_price + 25,
                         volume: 1_000_000)
          series.add_candle(candle)
        end

        # Add gap up
        gap_candle = build(:candle,
                           timestamp: 4.hours.ago,
                           open: 25_600.0, # Gap up from previous close
                           high: 25_700.0,
                           low: 25_550.0,
                           close: 25_650.0,
                           volume: 1_500_000)
        series.add_candle(gap_candle)
      end
    end

    trait :recent_data do
      after(:build) do |series|
        # Add recent candles (last 24 hours)
        24.times do |i|
          candle = build(:candle,
                         timestamp: Time.current - i.hours,
                         open: 25_000.0 + (i * 5),
                         high: 25_030.0 + (i * 5),
                         low: 24_970.0 + (i * 5),
                         close: 25_015.0 + (i * 5),
                         volume: 1_000_000)
          series.add_candle(candle)
        end
      end
    end

    trait :historical_data do
      after(:build) do |series|
        # Add historical candles (last 30 days)
        30.times do |i|
          candle = build(:candle,
                         timestamp: Time.current - i.days,
                         open: 25_000.0 + (i * 10),
                         high: 25_050.0 + (i * 10),
                         low: 24_950.0 + (i * 10),
                         close: 25_025.0 + (i * 10),
                         volume: 2_000_000)
          series.add_candle(candle)
        end
      end
    end

    trait :nifty_1m_with_trend do
      nifty_series
      one_minute
      bullish_trend
    end

    trait :banknifty_5m_sideways do
      banknifty_series
      five_minute
      sideways_trend
    end

    trait :sensex_daily_bearish do
      sensex_series
      daily
      bearish_trend
    end
  end
end
