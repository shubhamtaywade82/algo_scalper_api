# frozen_string_literal: true

FactoryBot.define do
  factory :trade_journal do
    position_tracker
    instrument
    strategy_name { 'Scalper' }
    side { 'LONG' }
    quantity { 15 }
    entry_price { 100.0 }
    entry_time { Time.current }
    paper { true }
  end
end
