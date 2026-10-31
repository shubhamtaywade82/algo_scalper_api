# frozen_string_literal: true

# The canonical balanced mandate (config/investing.yml mandates.balanced_v1,
# FY2026-27 review template — TDD §3.4). Shared by factories and specs so the
# worked example in the allocation specs always runs against a real 100% sum.
BALANCED_SLEEVES = {
  "indian_large_cap" => { group: "equity", pct: 25 },
  "indian_mid_small_cap" => { group: "equity", pct: 10 },
  "global_equity" => { group: "equity", pct: 10 },
  "technology_clean_energy" => { group: "equity", pct: 10 },
  "government_aaa_bonds" => { group: "fixed_income", pct: 15 },
  "short_duration_debt" => { group: "fixed_income", pct: 10 },
  "reits_invits" => { group: "real_assets", pct: 5 },
  "infrastructure_funds" => { group: "real_assets", pct: 7 },
  "cash_liquid_funds" => { group: "cash_alternatives", pct: 5 },
  "gold_silver_etfs" => { group: "cash_alternatives", pct: 3 }
}.freeze

FactoryBot.define do
  factory :investment_policy do
    investment_portfolio
    version { 1 }
    status { "draft" }
    effective_from { Date.current }
    constraints do
      { "max_single_stock_pct" => 2.5, "max_sector_pct" => 12, "max_illiquid_pct" => 25 }
    end
    rebalancing do
      { "bands" => {
          "equity" => { "lower_pct" => 50, "upper_pct" => 60 },
          "fixed_income" => { "lower_pct" => 20, "upper_pct" => 30 },
          "real_assets" => { "lower_pct" => 8, "upper_pct" => 16 },
          "cash_alternatives" => { "lower_pct" => 3, "upper_pct" => 12 }
        },
        "threshold_to_act_pct" => 1.0,
        "review_frequency" => "quarterly",
        "proposal_expiry_market_days" => 7 }
    end
    deployment do
      { "equity_tranches" => 3, "deployment_weeks" => 12, "midcap_stp_months" => 6 }
    end
    mandate_key { nil }

    trait :active do
      status { "active" }
    end

    trait :draft do
      status { "draft" }
    end

    trait :with_balanced_sleeves do
      after(:create) do |policy|
        BALANCED_SLEEVES.each_with_index do |(key, cfg), position|
          create(:investment_policy_sleeve, investment_policy: policy,
                                            sleeve_key: key,
                                            group_key: cfg[:group],
                                            target_pct: cfg[:pct],
                                            position: position)
        end
      end
    end

    # Active policy carrying the full balanced sleeve set.
    trait :balanced do
      active
      with_balanced_sleeves
    end
  end
end
