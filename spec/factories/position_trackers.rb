# frozen_string_literal: true

FactoryBot.define do
  factory :position_tracker do
    instrument
    sequence(:order_no) { |n| "ORD#{n.to_s.rjust(6, '0')}" }
    security_id { instrument.security_id }
    symbol { instrument.symbol_name }
    segment { instrument.segment }
    side { 'long_ce' }
    status { 'active' }
    quantity { 25 }
    avg_price { BigDecimal('25000.00') }
    entry_price { BigDecimal('25000.00') }
    last_pnl_rupees { BigDecimal('2500.00') }
    last_pnl_pct { BigDecimal('4.0') }
    high_water_mark_pnl { BigDecimal('25200.00') }
    meta { {} }

    trait :pending do
      status { 'pending' }
      avg_price { nil }
      entry_price { nil }
      last_pnl_rupees { BigDecimal('0.00') }
      last_pnl_pct { BigDecimal('0.0') }
      high_water_mark_pnl { nil }
    end

    trait :exited do
      status { 'exited' }
      last_pnl_rupees { BigDecimal('5000.00') }
      last_pnl_pct { BigDecimal('8.0') }
    end

    trait :cancelled do
      status { 'cancelled' }
      avg_price { nil }
      entry_price { nil }
      last_pnl_rupees { BigDecimal('0.00') }
      last_pnl_pct { BigDecimal('0.0') }
    end

    trait :long_position do
      side { 'long_ce' }
      quantity { 25 }
      avg_price { BigDecimal('25000.00') }
      entry_price { BigDecimal('25000.00') }
      last_pnl_rupees { BigDecimal('2500.00') }
      last_pnl_pct { BigDecimal('4.0') }
    end

    trait :short_position do
      side { 'short_pe' }
      quantity { -25 }
      avg_price { BigDecimal('25000.00') }
      entry_price { BigDecimal('25000.00') }
      last_pnl_rupees { BigDecimal('2500.00') }
      last_pnl_pct { BigDecimal('4.0') }
    end

    trait :profitable do
      last_pnl_rupees { BigDecimal('12500.00') }
      last_pnl_pct { BigDecimal('20.0') }
      high_water_mark_pnl { BigDecimal('25500.00') }
    end

    trait :losing do
      last_pnl_rupees { BigDecimal('-12500.00') }
      last_pnl_pct { BigDecimal('-20.0') }
    end

    trait :nifty_position do
      instrument factory: %i[instrument nifty_future]
      security_id { '12345' }
      segment { 'derivatives' }
      quantity { 25 }
      avg_price { BigDecimal('25000.00') }
      entry_price { BigDecimal('25000.00') }
    end

    trait :banknifty_position do
      instrument factory: %i[instrument banknifty_future]
      security_id { '67890' }
      segment { 'derivatives' }
      quantity { 15 }
      avg_price { BigDecimal('56000.00') }
      entry_price { BigDecimal('56000.00') }
    end

    trait :option_position do
      instrument factory: %i[instrument nifty_call_option]
      security_id { '11111' }
      segment { 'derivatives' }
      quantity { 25 }
      avg_price { BigDecimal('150.00') }
      entry_price { BigDecimal('150.00') }
      last_pnl_rupees { BigDecimal('250.00') }
      last_pnl_pct { BigDecimal('6.67') }
    end
  end
end
