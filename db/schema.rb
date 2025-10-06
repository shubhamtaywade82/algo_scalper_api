# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.0].define(version: 2025_10_11_000000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "derivatives", force: :cascade do |t|
    t.bigint "instrument_id", null: false
    t.string "exchange"
    t.string "segment"
    t.string "security_id"
    t.string "isin"
    t.string "instrument_code"
    t.string "underlying_security_id"
    t.string "underlying_symbol"
    t.string "symbol_name"
    t.string "display_name"
    t.string "instrument_type"
    t.string "series"
    t.integer "lot_size"
    t.date "expiry_date"
    t.decimal "strike_price"
    t.string "option_type"
    t.decimal "tick_size"
    t.string "expiry_flag"
    t.string "bracket_flag"
    t.string "cover_flag"
    t.string "asm_gsm_flag"
    t.string "asm_gsm_category"
    t.string "buy_sell_indicator"
    t.decimal "buy_co_min_margin_per"
    t.decimal "sell_co_min_margin_per"
    t.decimal "buy_co_sl_range_max_perc"
    t.decimal "sell_co_sl_range_max_perc"
    t.decimal "buy_co_sl_range_min_perc"
    t.decimal "sell_co_sl_range_min_perc"
    t.decimal "buy_bo_min_margin_per"
    t.decimal "sell_bo_min_margin_per"
    t.decimal "buy_bo_sl_range_max_perc"
    t.decimal "sell_bo_sl_range_max_perc"
    t.decimal "buy_bo_sl_range_min_perc"
    t.decimal "sell_bo_sl_min_range"
    t.decimal "buy_bo_profit_range_max_perc"
    t.decimal "sell_bo_profit_range_max_perc"
    t.decimal "buy_bo_profit_range_min_perc"
    t.decimal "sell_bo_profit_range_min_perc"
    t.decimal "mtf_leverage"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["instrument_code"], name: "index_derivatives_on_instrument_code"
    t.index ["instrument_id"], name: "index_derivatives_on_instrument_id"
    t.index ["security_id", "symbol_name", "exchange", "segment"], name: "index_derivatives_unique", unique: true
    t.index ["symbol_name"], name: "index_derivatives_on_symbol_name"
    t.index ["underlying_symbol", "expiry_date"], name: "index_derivatives_on_underlying_symbol_and_expiry_date", where: "(underlying_symbol IS NOT NULL)"
  end

  create_table "instruments", force: :cascade do |t|
    t.string "exchange", null: false
    t.string "segment", null: false
    t.string "security_id", null: false
    t.string "isin"
    t.string "instrument_code"
    t.string "underlying_security_id"
    t.string "underlying_symbol"
    t.string "symbol_name"
    t.string "display_name"
    t.string "instrument_type"
    t.string "series"
    t.integer "lot_size"
    t.date "expiry_date"
    t.decimal "strike_price", precision: 15, scale: 5
    t.string "option_type"
    t.decimal "tick_size"
    t.string "expiry_flag"
    t.string "bracket_flag"
    t.string "cover_flag"
    t.string "asm_gsm_flag"
    t.string "asm_gsm_category"
    t.string "buy_sell_indicator"
    t.decimal "buy_co_min_margin_per", precision: 8, scale: 2
    t.decimal "sell_co_min_margin_per", precision: 8, scale: 2
    t.decimal "buy_co_sl_range_max_perc", precision: 8, scale: 2
    t.decimal "sell_co_sl_range_max_perc", precision: 8, scale: 2
    t.decimal "buy_co_sl_range_min_perc", precision: 8, scale: 2
    t.decimal "sell_co_sl_range_min_perc", precision: 8, scale: 2
    t.decimal "buy_bo_min_margin_per", precision: 8, scale: 2
    t.decimal "sell_bo_min_margin_per", precision: 8, scale: 2
    t.decimal "buy_bo_sl_range_max_perc", precision: 8, scale: 2
    t.decimal "sell_bo_sl_range_max_perc", precision: 8, scale: 2
    t.decimal "buy_bo_sl_range_min_perc", precision: 8, scale: 2
    t.decimal "sell_bo_sl_min_range", precision: 8, scale: 2
    t.decimal "buy_bo_profit_range_max_perc", precision: 8, scale: 2
    t.decimal "sell_bo_profit_range_max_perc", precision: 8, scale: 2
    t.decimal "buy_bo_profit_range_min_perc", precision: 8, scale: 2
    t.decimal "sell_bo_profit_range_min_perc", precision: 8, scale: 2
    t.decimal "mtf_leverage", precision: 8, scale: 2
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["instrument_code"], name: "index_instruments_on_instrument_code"
    t.index ["security_id", "symbol_name", "exchange", "segment"], name: "index_instruments_unique", unique: true
    t.index ["symbol_name"], name: "index_instruments_on_symbol_name"
    t.index ["underlying_symbol", "expiry_date"], name: "index_instruments_on_underlying_symbol_and_expiry_date", where: "(underlying_symbol IS NOT NULL)"
  end

  create_table "settings", force: :cascade do |t|
    t.string "key", null: false
    t.text "value"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_settings_on_key", unique: true
  end

  create_table "watchlist_items", force: :cascade do |t|
    t.string "segment", null: false
    t.string "security_id", null: false
    t.integer "kind"
    t.string "label"
    t.boolean "active", default: true, null: false
    t.string "watchable_type"
    t.bigint "watchable_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["segment", "security_id"], name: "index_watchlist_items_on_segment_and_security_id", unique: true
    t.index ["watchable_type", "watchable_id"], name: "index_watchlist_items_on_watchable_type_and_watchable_id"
  end

  create_table "trade_logs", force: :cascade do |t|
    t.string "strategy", null: false
    t.string "symbol"
    t.string "segment", null: false
    t.string "security_id", null: false
    t.integer "direction", null: false
    t.integer "status", default: 0, null: false
    t.integer "quantity", null: false
    t.decimal "entry_price", precision: 15, scale: 4
    t.decimal "stop_price", precision: 15, scale: 4
    t.decimal "target_price", precision: 15, scale: 4
    t.decimal "risk_amount", precision: 15, scale: 4
    t.decimal "estimated_profit", precision: 15, scale: 4
    t.string "order_id"
    t.datetime "placed_at"
    t.string "exit_order_id"
    t.decimal "exit_price", precision: 15, scale: 4
    t.datetime "closed_at"
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["strategy", "security_id", "status"], name: "index_trade_logs_on_strategy_security_status"
    t.index ["strategy"], name: "index_trade_logs_on_strategy"
  end

  add_foreign_key "derivatives", "instruments"
end
