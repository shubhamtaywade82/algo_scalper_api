# frozen_string_literal: true

FactoryBot.define do
  factory :candle do
    timestamp { Time.current }
    open { 25_000.0 }
    high { 25_100.0 }
    low { 24_900.0 }
    close { 25_050.0 }
    volume { 1_000_000 }

    trait :bullish do
      open { 25_000.0 }
      high { 25_100.0 }
      low { 24_950.0 }
      close { 25_080.0 }
    end

    trait :bearish do
      open { 25_000.0 }
      high { 25_050.0 }
      low { 24_900.0 }
      close { 24_920.0 }
    end

    trait :doji do
      open { 25_000.0 }
      high { 25_020.0 }
      low { 24_980.0 }
      close { 25_000.0 }
    end

    trait :hammer do
      open { 25_000.0 }
      high { 25_050.0 }
      low { 24_800.0 }
      close { 25_020.0 }
    end

    trait :shooting_star do
      open { 25_000.0 }
      high { 25_200.0 }
      low { 24_980.0 }
      close { 25_010.0 }
    end

    trait :high_volume do
      volume { 5_000_000 }
    end

    trait :low_volume do
      volume { 100_000 }
    end

    trait :nifty_candle do
      open { 25_000.0 }
      high { 25_100.0 }
      low { 24_900.0 }
      close { 25_050.0 }
      volume { 2_000_000 }
    end

    trait :banknifty_candle do
      open { 56_000.0 }
      high { 56_200.0 }
      low { 55_800.0 }
      close { 56_100.0 }
      volume { 1_500_000 }
    end

    trait :sensex_candle do
      open { 82_000.0 }
      high { 82_500.0 }
      low { 81_800.0 }
      close { 82_300.0 }
      volume { 3_000_000 }
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
      open { 25_200.0 }
      high { 25_300.0 }
      low { 25_150.0 }
      close { 25_250.0 }
    end

    trait :with_gap_down do
      open { 24_800.0 }
      high { 24_900.0 }
      low { 24_700.0 }
      close { 24_850.0 }
    end

    trait :small_body do
      open { 25_000.0 }
      high { 25_020.0 }
      low { 24_980.0 }
      close { 25_010.0 }
    end

    trait :large_body do
      open { 25_000.0 }
      high { 25_200.0 }
      low { 24_800.0 }
      close { 25_150.0 }
    end

    trait :long_wick_high do
      open { 25_000.0 }
      high { 25_200.0 }
      low { 24_950.0 }
      close { 25_020.0 }
    end

    trait :long_wick_low do
      open { 25_000.0 }
      high { 25_050.0 }
      low { 24_800.0 }
      close { 24_980.0 }
    end

    trait :spinning_top do
      open { 25_000.0 }
      high { 25_030.0 }
      low { 24_970.0 }
      close { 25_005.0 }
    end

    trait :marubozu_bullish do
      open { 25_000.0 }
      high { 25_100.0 }
      low { 25_000.0 }
      close { 25_100.0 }
    end

    trait :marubozu_bearish do
      open { 25_000.0 }
      high { 25_000.0 }
      low { 24_900.0 }
      close { 24_900.0 }
    end
  end
end
