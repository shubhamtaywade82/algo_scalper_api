# frozen_string_literal: true

FactoryBot.define do
  factory :trade_memory do
    position_tracker
    symbol { position_tracker&.symbol || 'NIFTY' }
    strategy_name { 'test_strategy' }
    pnl_rupees { BigDecimal('1000.0') }
    exit_reason { 'take_profit' }
    lesson { 'Test lesson' }
    category { 'pattern_recognition' }
    confidence { 0.6 }
  end
end
