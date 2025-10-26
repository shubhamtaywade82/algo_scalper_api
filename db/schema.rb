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

ActiveRecord::Schema[8.0].define(version: 2025_10_26_104459) do
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

  create_table "position_trackers", force: :cascade do |t|
    t.bigint "instrument_id", null: false
    t.string "order_no", null: false
    t.string "security_id", null: false
    t.string "symbol"
    t.string "segment"
    t.string "side"
    t.string "status", default: "pending", null: false
    t.integer "quantity"
    t.decimal "avg_price", precision: 12, scale: 4
    t.decimal "entry_price", precision: 12, scale: 4
    t.decimal "last_pnl_rupees", precision: 12, scale: 4
    t.decimal "last_pnl_pct", precision: 8, scale: 4
    t.decimal "high_water_mark_pnl", precision: 12, scale: 4, default: "0.0"
    t.jsonb "meta", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["instrument_id"], name: "index_position_trackers_on_instrument_id"
    t.index ["order_no"], name: "index_position_trackers_on_order_no", unique: true
    t.index ["security_id", "status"], name: "index_position_trackers_on_security_id_and_status"
    t.index ["status"], name: "index_position_trackers_on_status"
  end

  create_table "settings", force: :cascade do |t|
    t.string "key", null: false
    t.text "value"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_settings_on_key", unique: true
  end

  create_table "trading_signals", force: :cascade do |t|
    t.string "index_key", null: false
    t.string "direction", null: false
    t.decimal "confidence_score", precision: 5, scale: 4
    t.string "timeframe", null: false
    t.decimal "supertrend_value", precision: 12, scale: 4
    t.decimal "adx_value", precision: 8, scale: 4
    t.datetime "signal_timestamp", null: false
    t.datetime "candle_timestamp", null: false
    t.jsonb "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["confidence_score"], name: "index_trading_signals_on_confidence_score"
    t.index ["direction", "signal_timestamp"], name: "index_trading_signals_on_direction_and_signal_timestamp"
    t.index ["index_key", "signal_timestamp"], name: "index_trading_signals_on_index_key_and_signal_timestamp"
    t.index ["metadata"], name: "index_trading_signals_on_metadata", using: :gin
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

  add_foreign_key "derivatives", "instruments"
  add_foreign_key "position_trackers", "instruments"
end
