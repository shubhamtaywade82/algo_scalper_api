# frozen_string_literal: true

FactoryBot.define do
  factory :trade_analytic do
    position_tracker
    symbol { position_tracker&.symbol || 'NIFTY' }
    entry_price { BigDecimal('100.0') }
    exit_price { BigDecimal('120.0') }
    max_favorable_excursion { BigDecimal('25.0') }
    max_adverse_excursion { BigDecimal('-8.0') }
    duration_seconds { 600 }
    strategy { 'test_strategy' }
    exit_reason { 'take_profit' }
    volatility { 0.0 }
  end
end
