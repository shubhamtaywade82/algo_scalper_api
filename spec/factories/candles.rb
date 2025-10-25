# frozen_string_literal: true

FactoryBot.define do
  factory :candle do
    timestamp { Time.current }
    open { 25000.0 }
    high { 25100.0 }
    low { 24900.0 }
    close { 25050.0 }
    volume { 1000000 }

    trait :bullish do
      open { 25000.0 }
      high { 25100.0 }
      low { 24950.0 }
      close { 25080.0 }
    end

    trait :bearish do
      open { 25000.0 }
      high { 25050.0 }
      low { 24900.0 }
      close { 24920.0 }
    end

    trait :doji do
      open { 25000.0 }
      high { 25020.0 }
      low { 24980.0 }
      close { 25000.0 }
    end

    trait :hammer do
      open { 25000.0 }
      high { 25050.0 }
      low { 24800.0 }
      close { 25020.0 }
    end

    trait :shooting_star do
      open { 25000.0 }
      high { 25200.0 }
      low { 24980.0 }
      close { 25010.0 }
    end

    trait :high_volume do
      volume { 5000000 }
    end

    trait :low_volume do
      volume { 100000 }
    end

    trait :nifty_candle do
      open { 25000.0 }
      high { 25100.0 }
      low { 24900.0 }
      close { 25050.0 }
      volume { 2000000 }
    end

    trait :banknifty_candle do
      open { 56000.0 }
      high { 56200.0 }
      low { 55800.0 }
      close { 56100.0 }
      volume { 1500000 }
    end

    trait :sensex_candle do
      open { 82000.0 }
      high { 82500.0 }
      low { 81800.0 }
      close { 82300.0 }
      volume { 3000000 }
    end

    trait :recent do
      timestamp { 1.hour.ago }
    end

    trait :old do
      timestamp { 1.day.ago }
    end

    trait :intraday do
      timestamp { Time.current.beginning_of_day + 9.hours + 30.minutes }
    end

    trait :end_of_day do
      timestamp { Time.current.beginning_of_day + 15.hours + 30.minutes }
    end

    trait :weekend do
      timestamp { Time.current.beginning_of_week + 6.days }
    end

    trait :holiday do
      timestamp { Date.new(2024, 1, 26).beginning_of_day + 9.hours + 30.minutes } # Republic Day
    end

    trait :with_gap_up do
      open { 25200.0 }
      high { 25300.0 }
      low { 25150.0 }
      close { 25250.0 }
    end

    trait :with_gap_down do
      open { 24800.0 }
      high { 24900.0 }
      low { 24700.0 }
      close { 24850.0 }
    end

    trait :small_body do
      open { 25000.0 }
      high { 25020.0 }
      low { 24980.0 }
      close { 25010.0 }
    end

    trait :large_body do
      open { 25000.0 }
      high { 25200.0 }
      low { 24800.0 }
      close { 25150.0 }
    end

    trait :long_wick_high do
      open { 25000.0 }
      high { 25200.0 }
      low { 24950.0 }
      close { 25020.0 }
    end

    trait :long_wick_low do
      open { 25000.0 }
      high { 25050.0 }
      low { 24800.0 }
      close { 24980.0 }
    end

    trait :spinning_top do
      open { 25000.0 }
      high { 25030.0 }
      low { 24970.0 }
      close { 25005.0 }
    end

    trait :marubozu_bullish do
      open { 25000.0 }
      high { 25100.0 }
      low { 25000.0 }
      close { 25100.0 }
    end

    trait :marubozu_bearish do
      open { 25000.0 }
      high { 25000.0 }
      low { 24900.0 }
      close { 24900.0 }
    end
  end
end
