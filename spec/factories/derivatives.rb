# == Schema Information
#
# Table name: derivatives
#
#  id                            :integer          not null, primary key
#  instrument_id                 :integer          not null
#  exchange                      :string
#  segment                       :string
#  security_id                   :string
#  isin                          :string
#  instrument_code               :string
#  underlying_security_id        :string
#  underlying_symbol             :string
#  symbol_name                   :string
#  display_name                  :string
#  instrument_type               :string
#  series                        :string
#  lot_size                      :integer
#  expiry_date                   :date
#  strike_price                  :decimal(, )
#  option_type                   :string
#  tick_size                     :decimal(, )
#  expiry_flag                   :string
#  bracket_flag                  :string
#  cover_flag                    :string
#  asm_gsm_flag                  :string
#  asm_gsm_category              :string
#  buy_sell_indicator            :string
#  buy_co_min_margin_per         :decimal(, )
#  sell_co_min_margin_per        :decimal(, )
#  buy_co_sl_range_max_perc      :decimal(, )
#  sell_co_sl_range_max_perc     :decimal(, )
#  buy_co_sl_range_min_perc      :decimal(, )
#  sell_co_sl_range_min_perc     :decimal(, )
#  buy_bo_min_margin_per         :decimal(, )
#  sell_bo_min_margin_per        :decimal(, )
#  buy_bo_sl_range_max_perc      :decimal(, )
#  sell_bo_sl_range_max_perc     :decimal(, )
#  buy_bo_sl_range_min_perc      :decimal(, )
#  sell_bo_sl_min_range          :decimal(, )
#  buy_bo_profit_range_max_perc  :decimal(, )
#  sell_bo_profit_range_max_perc :decimal(, )
#  buy_bo_profit_range_min_perc  :decimal(, )
#  sell_bo_profit_range_min_perc :decimal(, )
#  mtf_leverage                  :decimal(, )
#  created_at                    :datetime         not null
#  updated_at                    :datetime         not null
#
# Indexes
#
#  index_derivatives_on_instrument_code                    (instrument_code)
#  index_derivatives_on_instrument_id                      (instrument_id)
#  index_derivatives_on_symbol_name                        (symbol_name)
#  index_derivatives_on_underlying_symbol_and_expiry_date  (underlying_symbol,expiry_date)
#  index_derivatives_unique                                (security_id,symbol_name,exchange,segment) UNIQUE
#

# frozen_string_literal: true

FactoryBot.define do
  factory :derivative do
    instrument
    sequence(:security_id) { |n| (20_000 + n).to_s }
    symbol_name { instrument.symbol_name }
    exchange { instrument.exchange }
    segment { 'derivatives' }
    isin { 'INE987654321' }
    instrument_code { 'futures_index' }
    underlying_security_id { instrument.security_id }
    underlying_symbol { instrument.symbol_name }
    display_name { "#{instrument.symbol_name} Future" }
    instrument_type { 'FUTURE' }
    series { 'EQ' }
    lot_size { instrument.lot_size }
    expiry_date { 1.month.from_now }
    strike_price { nil }
    option_type { nil }
    tick_size { instrument.tick_size }
    expiry_flag { false }
    bracket_flag { false }
    cover_flag { false }
    asm_gsm_flag { false }
    asm_gsm_category { 'NORMAL' }
    buy_sell_indicator { 'BOTH' }
    buy_co_min_margin_per { 10.0 }
    sell_co_min_margin_per { 10.0 }
    buy_co_sl_range_max_perc { 20.0 }
    sell_co_sl_range_max_perc { 20.0 }
    buy_co_sl_range_min_perc { 5.0 }
    sell_co_sl_range_min_perc { 5.0 }
    buy_bo_min_margin_per { 15.0 }
    sell_bo_min_margin_per { 15.0 }
    buy_bo_sl_range_max_perc { 25.0 }
    sell_bo_sl_range_max_perc { 25.0 }
    buy_bo_sl_range_min_perc { 3.0 }
    sell_bo_sl_min_range { 3.0 }
    buy_bo_profit_range_max_perc { 30.0 }
    sell_bo_profit_range_max_perc { 30.0 }
    buy_bo_profit_range_min_perc { 2.0 }
    sell_bo_profit_range_min_perc { 2.0 }
    mtf_leverage { 1.0 }

    trait :future do
      instrument_type { 'FUTURE' }
      strike_price { nil }
      option_type { nil }
    end

    trait :call_option do
      instrument_type { 'OPTION' }
      option_type { 'CE' }
      strike_price { 25_000 }
      display_name { "#{symbol_name} #{strike_price} CE" }
    end

    trait :put_option do
      instrument_type { 'OPTION' }
      option_type { 'PE' }
      strike_price { 25_000 }
      display_name { "#{symbol_name} #{strike_price} PE" }
    end

    trait :nifty_future do
      instrument factory: %i[instrument nifty_index]
      security_id { '12345' }
      symbol_name { 'NIFTY' }
      exchange { 'NSE' }
      segment { 'derivatives' }
      underlying_security_id { '13' }
      underlying_symbol { 'NIFTY' }
      instrument_type { 'FUTURE' }
      lot_size { 25 }
      expiry_date { 1.month.from_now }
    end

    trait :nifty_call_option do
      instrument factory: %i[instrument nifty_index]
      security_id { '11111' }
      symbol_name { 'NIFTY' }
      exchange { 'NSE' }
      segment { 'derivatives' }
      underlying_security_id { '13' }
      underlying_symbol { 'NIFTY' }
      instrument_type { 'OPTION' }
      lot_size { 25 }
      expiry_date { 1.month.from_now }
      strike_price { 25_000 }
      option_type { 'CE' }
      display_name { 'NIFTY 25000 CE' }
    end

    trait :nifty_put_option do
      instrument factory: %i[instrument nifty_index]
      security_id { '22222' }
      symbol_name { 'NIFTY' }
      exchange { 'NSE' }
      segment { 'derivatives' }
      underlying_security_id { '13' }
      underlying_symbol { 'NIFTY' }
      instrument_type { 'OPTION' }
      lot_size { 25 }
      expiry_date { 1.month.from_now }
      strike_price { 25_000 }
      option_type { 'PE' }
      display_name { 'NIFTY 25000 PE' }
    end

    trait :banknifty_future do
      instrument factory: %i[instrument banknifty_index]
      security_id { '67890' }
      symbol_name { 'BANKNIFTY' }
      exchange { 'NSE' }
      segment { 'derivatives' }
      underlying_security_id { '25' }
      underlying_symbol { 'BANKNIFTY' }
      instrument_type { 'FUTURE' }
      lot_size { 15 }
      expiry_date { 1.month.from_now }
    end

    trait :banknifty_call_option do
      instrument factory: %i[instrument banknifty_index]
      security_id { '33333' }
      symbol_name { 'BANKNIFTY' }
      exchange { 'NSE' }
      segment { 'derivatives' }
      underlying_security_id { '25' }
      underlying_symbol { 'BANKNIFTY' }
      instrument_type { 'OPTION' }
      lot_size { 15 }
      expiry_date { 1.month.from_now }
      strike_price { 56_000 }
      option_type { 'CE' }
      display_name { 'BANKNIFTY 56000 CE' }
    end

    trait :banknifty_put_option do
      instrument factory: %i[instrument banknifty_index]
      security_id { '44444' }
      symbol_name { 'BANKNIFTY' }
      exchange { 'NSE' }
      segment { 'derivatives' }
      underlying_security_id { '25' }
      underlying_symbol { 'BANKNIFTY' }
      instrument_type { 'OPTION' }
      lot_size { 15 }
      expiry_date { 1.month.from_now }
      strike_price { 56_000 }
      option_type { 'PE' }
      display_name { 'BANKNIFTY 56000 PE' }
    end

    trait :currency_future do
      instrument factory: %i[instrument currency_future]
      security_id { '55555' }
      symbol_name { 'USDINR' }
      exchange { 'NSE' }
      segment { 'currency' }
      instrument_type { 'FUTURE' }
      lot_size { 1000 }
      expiry_date { 1.month.from_now }
    end

    trait :atm_call_option do
      call_option
      strike_price { 25_000 }
      display_name { "#{symbol_name} #{strike_price} CE" }
    end

    trait :atm_put_option do
      put_option
      strike_price { 25_000 }
      display_name { "#{symbol_name} #{strike_price} PE" }
    end

    trait :otm_call_option do
      call_option
      strike_price { 25_500 }
      display_name { "#{symbol_name} #{strike_price} CE" }
    end

    trait :otm_put_option do
      put_option
      strike_price { 24_500 }
      display_name { "#{symbol_name} #{strike_price} PE" }
    end

    trait :itm_call_option do
      call_option
      strike_price { 24_500 }
      display_name { "#{symbol_name} #{strike_price} CE" }
    end

    trait :itm_put_option do
      put_option
      strike_price { 25_500 }
      display_name { "#{symbol_name} #{strike_price} PE" }
    end
  end
end
