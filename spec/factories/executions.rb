# frozen_string_literal: true

FactoryBot.define do
  factory :execution do
    instrument
    position_tracker { nil }
    sequence(:order_no) { |n| "EXEC#{n.to_s.rjust(8, '0')}" }
    side { 'buy' }
    purpose { 'entry' }
    source { 'paper' }
    status { 'filled' }
    quantity { 25 }
    fill_price { BigDecimal('150.00') }
    requested_price { BigDecimal('149.90') }
    bid { BigDecimal('149.80') }
    ask { BigDecimal('150.05') }
    filled_at { Time.current }
    meta { {} }

    trait :exit do
      purpose { 'exit' }
      side { 'sell' }
    end

    trait :live do
      source { 'live' }
    end

    trait :pending do
      status { 'pending' }
      fill_price { nil }
      filled_at { nil }
    end
  end
end
