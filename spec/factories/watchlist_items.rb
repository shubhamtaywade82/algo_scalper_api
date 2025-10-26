# frozen_string_literal: true

FactoryBot.define do
  factory :watchlist_item do
    sequence(:security_id) { |n| (10_000 + n).to_s }
    segment { 'NSE_FNO' }
    active { true }
    kind { :derivative }

    trait :for_instrument do
      watchable factory: %i[instrument]
      security_id { watchable.security_id }
      segment { watchable.segment }
    end

    trait :for_derivative do
      watchable factory: %i[derivative]
      security_id { watchable.security_id }
      segment { watchable.segment }
    end

    trait :nifty_index do
      security_id { '13' }
      segment { 'IDX_I' }
      kind { :index_value }
    end

    trait :banknifty_index do
      security_id { '25' }
      segment { 'IDX_I' }
      kind { :index_value }
    end

    trait :sensex_index do
      security_id { '51' }
      segment { 'BSE_IDX' }
      kind { :index_value }
    end

    trait :nifty_future do
      security_id { '12345' }
      segment { 'NSE_FNO' }
      kind { :derivative }
    end

    trait :banknifty_future do
      security_id { '67890' }
      segment { 'NSE_FNO' }
      kind { :derivative }
    end

    trait :nifty_call_option do
      security_id { '11111' }
      segment { 'NSE_FNO' }
      kind { :derivative }
    end

    trait :nifty_put_option do
      security_id { '22222' }
      segment { 'NSE_FNO' }
      kind { :derivative }
    end

    trait :banknifty_call_option do
      security_id { '33333' }
      segment { 'NSE_FNO' }
      kind { :derivative }
    end

    trait :banknifty_put_option do
      security_id { '44444' }
      segment { 'NSE_FNO' }
      kind { :derivative }
    end

    trait :currency_future do
      security_id { '55555' }
      segment { 'NSE_CURRENCY' }
      kind { :currency }
    end

    trait :equity do
      security_id { '66666' }
      segment { 'NSE_EQ' }
      kind { :equity }
    end

    trait :commodity do
      security_id { '77777' }
      segment { 'MCX_COMM' }
      kind { :commodity }
    end

    trait :inactive do
      active { false }
    end

    trait :active do
      active { true }
    end
  end
end
