# frozen_string_literal: true

FactoryBot.define do
  factory :investment_portfolio do
    sequence(:name) { |n| "Test Portfolio #{n}" }
    base_currency { "INR" }
    investment_horizon_years { 10 }
    risk_profile { "balanced" }
    status { "active" }
    broker_linkage { "manual" }
    external_ref { {} }
  end

  factory :investment_portfolio_with_dhan, parent: :investment_portfolio do
    broker_linkage { "dhan" }
    external_ref { { "dhan_client_id" => "1000000003" } }
  end
end
