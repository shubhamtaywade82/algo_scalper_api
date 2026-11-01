# frozen_string_literal: true

# Investing-domain factories (TDD §16 Phase 1). Equity instruments reuse the
# shared :instrument factory but pin the segment to NSE_EQ — the CNC product
# type (TDD §11.2) only exists on the equity segment.
FactoryBot.define do
  # Equity-segment instrument for CNC holdings (TDD §11.2) — the shared
  # :instrument factory defaults to derivatives, which is wrong for the
  # Investing domain (never derivatives, §1.3.2).
  factory :equity_instrument, parent: :instrument do
    exchange { "nse" }
    segment { "equity" }
    instrument_type { "EQUITY" }
    # enum :instrument_code — :equity maps to 'EQUITY' (instrument_helpers.rb)
    instrument_code { "equity" }
    expiry_date { nil }
    strike_price { nil }
  end

  factory :investment_portfolio do
    sequence(:name) { |n| "investing-#{n}" }
    mode { "paper" }
    base_currency { "INR" }
    cash_balance { "100000.00" }
    invested_amount { "0.00" }
    meta { { "mandate" => "balanced_v1" } }
  end

  factory :investment_policy do
    investment_portfolio
    mandate_version { "balanced_v1" }
    status { "draft" }
    constraints { { "max_single_stock_pct" => 2.5 } }
    rebalance_band_min_pct { "50" }
    rebalance_band_max_pct { "60" }

    transient do
      with_sleeves { false }
    end

    after(:build) do |policy, evaluator|
      if evaluator.with_sleeves && policy.allocation_sleeves.empty?
        # FY2026-27 illustrative default — must mirror config/investing.yml
        # and sum to EXACTLY 100 (TDD §5.2 / §16 A1.2/A1.3).
        sleeves = [
          ["large_cap_core", "Large-Cap Core (Nifty 100)", "equity", 25],
          ["mid_small_cap", "Mid & Small Cap Growth", "equity", 10],
          ["global_equity", "Global Equity", "equity", 10],
          ["thematic_tech_clean", "Tech & Clean Energy", "equity", 10],
          ["govt_aaa_bonds", "Govt/AAA Bonds", "debt", 15],
          ["short_duration_debt", "Short-Duration Debt / Liquid", "debt", 10],
          ["reit_invit", "REITs & InvITs", "reit", 5],
          ["infra", "Infrastructure", "infra", 7],
          ["cash", "Cash & Equivalents", "cash", 5],
          ["gold_silver", "Gold & Silver", "gold", 3]
        ]
        sleeves.each_with_index do |(key, name, asset_class, weight), i|
          policy.allocation_sleeves.build(
            sleeve_key: key, sleeve_name: name, asset_class: asset_class,
            target_weight_pct: weight, display_order: i
          )
        end
      end
    end
  end

  factory :allocation_sleeve do
    investment_policy
    sleeve_key { "large_cap_core" }
    sleeve_name { "Large-Cap Core (Nifty 100)" }
    asset_class { "equity" }
    target_weight_pct { "25" }
    display_order { 0 }
  end

  factory :investment_holding do
    investment_portfolio
    instrument factory: :equity_instrument
    sleeve_key { "large_cap_core" }
    quantity { "100" }
    # settled + settling must equal total (model invariant); default: all settled
    available_quantity { quantity }
    t1_quantity { "0" }
    average_cost_price { "1500.0000" }
    last_price { "1600.0000" }
    is_illiquid { false }

    trait :t1_pending do
      quantity { "110" }
      available_quantity { "100" }
      t1_quantity { "10" }
    end

    trait :illiquid do
      is_illiquid { true }
      sleeve_key { "reit_invit" }
    end
  end

  factory :investment_lot do
    investment_holding
    quantity { "60" }
    remaining_quantity { "60" }
    buy_price { "1450.0000" }
    acquired_on { 30.days.ago.to_date }
    lot_source { "order" }

    trait :older do
      acquired_on { 60.days.ago.to_date }
      buy_price { "1400.0000" }
    end

    trait :partially_consumed do
      quantity { "60" }
      remaining_quantity { "25" }
    end

    trait :today do
      acquired_on { Time.current.in_time_zone("Asia/Kolkata").to_date }
    end
  end

  factory :investment_snapshot do
    investment_portfolio
    as_of_date { Time.current.in_time_zone("Asia/Kolkata").to_date }
    total_value { "100000.00" }
    cash_balance { "100000.00" }
    invested_value { "0.00" }
    sleeve_weights { { "cash" => "100.0" } }
  end

  factory :investment_transaction do
    investment_portfolio
    txn_type { "deposit" }
    amount { "100000.00" }
    quantity_delta { 0 }
  end
end
