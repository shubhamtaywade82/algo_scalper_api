# == Schema Information
#
# Table name: instruments
#
#  id                            :integer          not null, primary key
#  exchange                      :string           not null
#  segment                       :string           not null
#  security_id                   :string           not null
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
#  strike_price                  :decimal(15, 5)
#  option_type                   :string
#  tick_size                     :decimal(, )
#  expiry_flag                   :string
#  bracket_flag                  :string
#  cover_flag                    :string
#  asm_gsm_flag                  :string
#  asm_gsm_category              :string
#  buy_sell_indicator            :string
#  buy_co_min_margin_per         :decimal(8, 2)
#  sell_co_min_margin_per        :decimal(8, 2)
#  buy_co_sl_range_max_perc      :decimal(8, 2)
#  sell_co_sl_range_max_perc     :decimal(8, 2)
#  buy_co_sl_range_min_perc      :decimal(8, 2)
#  sell_co_sl_range_min_perc     :decimal(8, 2)
#  buy_bo_min_margin_per         :decimal(8, 2)
#  sell_bo_min_margin_per        :decimal(8, 2)
#  buy_bo_sl_range_max_perc      :decimal(8, 2)
#  sell_bo_sl_range_max_perc     :decimal(8, 2)
#  buy_bo_sl_range_min_perc      :decimal(8, 2)
#  sell_bo_sl_min_range          :decimal(8, 2)
#  buy_bo_profit_range_max_perc  :decimal(8, 2)
#  sell_bo_profit_range_max_perc :decimal(8, 2)
#  buy_bo_profit_range_min_perc  :decimal(8, 2)
#  sell_bo_profit_range_min_perc :decimal(8, 2)
#  mtf_leverage                  :decimal(8, 2)
#  created_at                    :datetime         not null
#  updated_at                    :datetime         not null
#
# Indexes
#
#  index_instruments_on_instrument_code                    (instrument_code)
#  index_instruments_on_symbol_name                        (symbol_name)
#  index_instruments_on_underlying_symbol_and_expiry_date  (underlying_symbol,expiry_date)
#  index_instruments_unique                                (security_id,symbol_name,exchange,segment) UNIQUE
#

# frozen_string_literal: true

FactoryBot.define do
  factory :instrument do
    sequence(:security_id) { |n| (10000 + n).to_s }
    sequence(:symbol_name) { |n| "SYMBOL#{n}" }
    exchange { "nse" }
    segment { "derivatives" }
    isin { "INE123456789" }
    instrument_code { "futures_index" }
    underlying_security_id { "12345" }
    underlying_symbol { "UNDERLYING" }
    display_name { "Display Name" }
    instrument_type { "FUTURE" }
    series { "EQ" }
    lot_size { 25 }
    expiry_date { 1.month.from_now }
    strike_price { nil }
    option_type { nil }
    tick_size { 0.05 }
    expiry_flag { false }
    bracket_flag { false }
    cover_flag { false }
    asm_gsm_flag { false }
    asm_gsm_category { "NORMAL" }
    buy_sell_indicator { "BOTH" }
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

    trait :nifty_index do
      security_id { "13" }
      symbol_name { "NIFTY" }
      exchange { "nse" }
      segment { "index" }
      instrument_code { "index" }
      instrument_type { "INDEX" }
      lot_size { 1 }
      tick_size { 0.05 }
    end

    trait :banknifty_index do
      security_id { "25" }
      symbol_name { "BANKNIFTY" }
      exchange { "nse" }
      segment { "index" }
      instrument_code { "index" }
      instrument_type { "INDEX" }
      lot_size { 1 }
      tick_size { 0.05 }
    end

    trait :sensex_index do
      security_id { "51" }
      symbol_name { "SENSEX" }
      exchange { "bse" }
      segment { "index" }
      instrument_code { "index" }
      instrument_type { "INDEX" }
      lot_size { 1 }
      tick_size { 0.05 }
    end

    trait :nifty_future do
      symbol_name { "NIFTY" }
      exchange { "nse" }
      segment { "derivatives" }
      instrument_code { "futures_index" }
      instrument_type { "FUTURE" }
      lot_size { 25 }
      expiry_date { 1.month.from_now }
    end

    trait :nifty_call_option do
      symbol_name { "NIFTY" }
      exchange { "nse" }
      segment { "derivatives" }
      instrument_code { "options_index" }
      instrument_type { "OPTION" }
      lot_size { 25 }
      expiry_date { 1.month.from_now }
      strike_price { 25000 }
      option_type { "CE" }
    end

    trait :nifty_put_option do
      symbol_name { "NIFTY" }
      exchange { "nse" }
      segment { "derivatives" }
      instrument_code { "options_index" }
      instrument_type { "OPTION" }
      lot_size { 25 }
      expiry_date { 1.month.from_now }
      strike_price { 25000 }
      option_type { "PE" }
    end

    trait :banknifty_future do
      symbol_name { "BANKNIFTY" }
      exchange { "nse" }
      segment { "derivatives" }
      instrument_code { "futures_index" }
      instrument_type { "FUTURE" }
      lot_size { 15 }
      expiry_date { 1.month.from_now }
    end

    trait :banknifty_call_option do
      symbol_name { "BANKNIFTY" }
      exchange { "nse" }
      segment { "derivatives" }
      instrument_code { "options_index" }
      instrument_type { "OPTION" }
      lot_size { 15 }
      expiry_date { 1.month.from_now }
      strike_price { 56000 }
      option_type { "CE" }
    end

    trait :banknifty_put_option do
      symbol_name { "BANKNIFTY" }
      exchange { "nse" }
      segment { "derivatives" }
      instrument_code { "options_index" }
      instrument_type { "OPTION" }
      lot_size { 15 }
      expiry_date { 1.month.from_now }
      strike_price { 56000 }
      option_type { "PE" }
    end

    trait :currency_future do
      symbol_name { "USDINR" }
      exchange { "nse" }
      segment { "currency" }
      instrument_code { "futures_currency" }
      instrument_type { "FUTURE" }
      lot_size { 1000 }
      expiry_date { 1.month.from_now }
    end

    trait :equity do
      symbol_name { "RELIANCE" }
      exchange { "nse" }
      segment { "equity" }
      instrument_code { "equity" }
      instrument_type { "EQ" }
      lot_size { 1 }
      tick_size { 0.05 }
    end
  end
end
