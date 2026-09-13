# frozen_string_literal: true

FactoryBot.define do
  factory :leg_group do
    sequence(:group_id) { |n| "LG#{n.to_s.rjust(8, '0')}" }
    instrument { nil }
    strategy_type { 'bull_call_spread' }
    underlying_symbol { 'NIFTY' }
    expiry { 1.week.from_now }
    quantity { 25 }
    status { 'active' }
    meta { {} }

    trait :closed do
      status { 'closed' }
    end

    trait :partial do
      status { 'partial' }
    end
  end
end
