# frozen_string_literal: true

FactoryBot.define do
  factory :order_intent do
    instrument
    strategy_name { 'smc_momentum' }
    side { 'BUY' }
    quantity { 75 }
    order_type { 'MARKET' }
    product_type { 'INTRADAY' }
    validity { 'DAY' }
    status { 'created' }
    meta { {} }
  end
end
