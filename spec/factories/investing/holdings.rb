# frozen_string_literal: true

FactoryBot.define do
  factory :investment_policy_sleeve do
    investment_policy
    sleeve_key { "indian_large_cap" }
    group_key { "equity" }
    target_pct { 25 }
    position { 0 }
    instrument_filter { {} }
  end

  factory :investment_holding do
    investment_portfolio
    instrument
    sleeve_key { "indian_large_cap" }
    source { "manual" }
    quantity { 10 }
    average_cost { BigDecimal("100") }
    last_price { BigDecimal("100") }
    last_valued_at { Time.current }

    trait :dhan_synced do
      source { "dhan_sync" }
      synced_at { Time.current }
      broker_raw do
        { "totalQty" => 10, "dpQty" => 10, "t1Qty" => 0, "availableQty" => 10,
          "collateralQty" => 0, "avgCostPrice" => 100.0 }
      end
    end

    trait :external do
      source { "external" }
      externally_held { true }
    end
  end
end
