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

ActiveRecord::Schema[8.1].define(version: 2026_04_07_120000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "algo_config_change_logs", force: :cascade do |t|
    t.string "actor"
    t.string "changed_paths", default: [], null: false, array: true
    t.datetime "created_at", null: false
    t.jsonb "metadata", default: {}, null: false
    t.jsonb "patch", default: {}, null: false
    t.string "request_id"
    t.string "source", null: false
    t.datetime "updated_at", null: false
    t.index ["changed_paths"], name: "index_algo_config_change_logs_on_paths", using: :gin
    t.index ["created_at"], name: "index_algo_config_change_logs_on_created_at"
    t.index ["source"], name: "index_algo_config_change_logs_on_source"
  end

  create_table "best_indicator_params", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "indicator", null: false
    t.bigint "instrument_id", null: false
    t.string "interval", null: false
    t.jsonb "metrics", default: {}, null: false
    t.jsonb "params", default: {}, null: false
    t.decimal "score", precision: 12, scale: 6, default: "0.0", null: false
    t.datetime "updated_at", null: false
    t.index ["instrument_id", "interval", "indicator"], name: "idx_unique_best_params_per_instrument_interval_indicator", unique: true
    t.index ["instrument_id"], name: "index_best_indicator_params_on_instrument_id"
    t.index ["metrics"], name: "index_best_indicator_params_on_metrics", using: :gin
    t.index ["params"], name: "index_best_indicator_params_on_params", using: :gin
  end

  create_table "derivatives", force: :cascade do |t|
    t.string "asm_gsm_category"
    t.string "asm_gsm_flag"
    t.string "bracket_flag"
    t.decimal "buy_bo_min_margin_per"
    t.decimal "buy_bo_profit_range_max_perc"
    t.decimal "buy_bo_profit_range_min_perc"
    t.decimal "buy_bo_sl_range_max_perc"
    t.decimal "buy_bo_sl_range_min_perc"
    t.decimal "buy_co_min_margin_per"
    t.decimal "buy_co_sl_range_max_perc"
    t.decimal "buy_co_sl_range_min_perc"
    t.string "buy_sell_indicator"
    t.string "cover_flag"
    t.datetime "created_at", null: false
    t.string "display_name"
    t.string "exchange"
    t.date "expiry_date"
    t.string "expiry_flag"
    t.string "instrument_code"
    t.bigint "instrument_id", null: false
    t.string "instrument_type"
    t.string "isin"
    t.integer "lot_size"
    t.decimal "mtf_leverage"
    t.string "option_type"
    t.string "security_id"
    t.string "segment"
    t.decimal "sell_bo_min_margin_per"
    t.decimal "sell_bo_profit_range_max_perc"
    t.decimal "sell_bo_profit_range_min_perc"
    t.decimal "sell_bo_sl_min_range"
    t.decimal "sell_bo_sl_range_max_perc"
    t.decimal "sell_co_min_margin_per"
    t.decimal "sell_co_sl_range_max_perc"
    t.decimal "sell_co_sl_range_min_perc"
    t.string "series"
    t.decimal "strike_price"
    t.string "symbol_name"
    t.decimal "tick_size"
    t.string "underlying_security_id"
    t.string "underlying_symbol"
    t.datetime "updated_at", null: false
    t.index ["expiry_date", "strike_price", "option_type"], name: "index_derivatives_on_expiry_strike_option_type"
    t.index ["instrument_code"], name: "index_derivatives_on_instrument_code"
    t.index ["instrument_id", "instrument_type"], name: "index_derivatives_on_instrument_id_and_instrument_type"
    t.index ["instrument_id"], name: "index_derivatives_on_instrument_id"
    t.index ["security_id", "symbol_name", "exchange", "segment"], name: "index_derivatives_unique", unique: true
    t.index ["symbol_name"], name: "index_derivatives_on_symbol_name"
    t.index ["underlying_symbol", "expiry_date"], name: "index_derivatives_on_underlying_symbol_and_expiry_date", where: "(underlying_symbol IS NOT NULL)"
  end

  create_table "dhan_access_tokens", force: :cascade do |t|
    t.string "token", null: false
    t.datetime "expiry_time", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["expiry_time"], name: "index_dhan_access_tokens_on_expiry_time"
  end

  create_table "instruments", force: :cascade do |t|
    t.string "asm_gsm_category"
    t.string "asm_gsm_flag"
    t.string "bracket_flag"
    t.decimal "buy_bo_min_margin_per", precision: 8, scale: 2
    t.decimal "buy_bo_profit_range_max_perc", precision: 8, scale: 2
    t.decimal "buy_bo_profit_range_min_perc", precision: 8, scale: 2
    t.decimal "buy_bo_sl_range_max_perc", precision: 8, scale: 2
    t.decimal "buy_bo_sl_range_min_perc", precision: 8, scale: 2
    t.decimal "buy_co_min_margin_per", precision: 8, scale: 2
    t.decimal "buy_co_sl_range_max_perc", precision: 8, scale: 2
    t.decimal "buy_co_sl_range_min_perc", precision: 8, scale: 2
    t.string "buy_sell_indicator"
    t.string "cover_flag"
    t.datetime "created_at", null: false
    t.string "display_name"
    t.string "exchange", null: false
    t.date "expiry_date"
    t.string "expiry_flag"
    t.string "instrument_code"
    t.string "instrument_type"
    t.string "isin"
    t.integer "lot_size"
    t.decimal "mtf_leverage", precision: 8, scale: 2
    t.string "option_type"
    t.string "security_id", null: false
    t.string "segment", null: false
    t.decimal "sell_bo_min_margin_per", precision: 8, scale: 2
    t.decimal "sell_bo_profit_range_max_perc", precision: 8, scale: 2
    t.decimal "sell_bo_profit_range_min_perc", precision: 8, scale: 2
    t.decimal "sell_bo_sl_min_range", precision: 8, scale: 2
    t.decimal "sell_bo_sl_range_max_perc", precision: 8, scale: 2
    t.decimal "sell_co_min_margin_per", precision: 8, scale: 2
    t.decimal "sell_co_sl_range_max_perc", precision: 8, scale: 2
    t.decimal "sell_co_sl_range_min_perc", precision: 8, scale: 2
    t.string "series"
    t.decimal "strike_price", precision: 15, scale: 5
    t.string "symbol_name"
    t.decimal "tick_size"
    t.string "underlying_security_id"
    t.string "underlying_symbol"
    t.datetime "updated_at", null: false
    t.index ["instrument_code"], name: "index_instruments_on_instrument_code"
    t.index ["security_id", "segment"], name: "index_instruments_on_security_id_and_segment"
    t.index ["security_id", "symbol_name", "exchange", "segment"], name: "index_instruments_unique", unique: true
    t.index ["symbol_name"], name: "index_instruments_on_symbol_name"
    t.index ["underlying_symbol", "expiry_date"], name: "index_instruments_on_underlying_symbol_and_expiry_date", where: "(underlying_symbol IS NOT NULL)"
  end

  create_table "paper_daily_wallets", force: :cascade do |t|
    t.decimal "closing_cash", precision: 18, scale: 2, default: "0.0", null: false
    t.datetime "created_at", null: false
    t.decimal "fees_total", precision: 18, scale: 2, default: "0.0", null: false
    t.decimal "gross_pnl", precision: 18, scale: 2, default: "0.0", null: false
    t.decimal "max_drawdown", precision: 18, scale: 2, default: "0.0", null: false
    t.decimal "max_equity", precision: 18, scale: 2, default: "0.0", null: false
    t.jsonb "meta", default: {}, null: false
    t.decimal "min_equity", precision: 18, scale: 2, default: "0.0", null: false
    t.decimal "net_pnl", precision: 18, scale: 2, default: "0.0", null: false
    t.decimal "opening_cash", precision: 18, scale: 2, default: "0.0", null: false
    t.integer "trades_count", default: 0, null: false
    t.date "trading_date", null: false
    t.datetime "updated_at", null: false
    t.index ["trading_date"], name: "index_paper_daily_wallets_on_trading_date", unique: true
  end

  create_table "paper_fills_logs", force: :cascade do |t|
    t.decimal "charge", precision: 10, scale: 2, default: "20.0", null: false
    t.datetime "created_at", null: false
    t.string "exchange_segment", null: false
    t.datetime "executed_at", null: false
    t.decimal "gross_value", precision: 14, scale: 2, null: false
    t.jsonb "meta", default: {}, null: false
    t.decimal "net_value", precision: 14, scale: 2, null: false
    t.decimal "price", precision: 12, scale: 2, null: false
    t.integer "qty", null: false
    t.bigint "security_id", null: false
    t.string "side", null: false
    t.date "trading_date", null: false
    t.datetime "updated_at", null: false
    t.index ["trading_date", "exchange_segment", "security_id"], name: "index_paper_fills_on_date_seg_sid"
  end

  create_table "paper_orders", force: :cascade do |t|
    t.string "correlation_id"
    t.datetime "created_at", null: false
    t.text "error_message"
    t.decimal "executed_price", precision: 15, scale: 2
    t.bigint "instrument_id", null: false
    t.jsonb "meta", default: {}
    t.string "order_no", null: false
    t.string "order_type", default: "MARKET"
    t.decimal "price", precision: 15, scale: 2
    t.string "product_type", default: "INTRADAY"
    t.integer "quantity", null: false
    t.string "security_id", null: false
    t.string "segment", null: false
    t.string "status", default: "pending"
    t.string "symbol"
    t.string "transaction_type", null: false
    t.datetime "updated_at", null: false
    t.index ["instrument_id"], name: "index_paper_orders_on_instrument_id"
    t.index ["order_no"], name: "index_paper_orders_on_order_no", unique: true
    t.index ["security_id"], name: "index_paper_orders_on_security_id"
    t.index ["status"], name: "index_paper_orders_on_status"
  end

  create_table "paper_positions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.decimal "current_price", precision: 15, scale: 2
    t.decimal "entry_price", precision: 15, scale: 2, null: false
    t.decimal "high_water_mark_pnl", precision: 15, scale: 2, default: "0.0"
    t.bigint "instrument_id", null: false
    t.jsonb "meta", default: {}
    t.bigint "paper_order_id", null: false
    t.decimal "pnl_percent", precision: 10, scale: 4, default: "0.0"
    t.decimal "pnl_rupees", precision: 15, scale: 2, default: "0.0"
    t.integer "quantity", null: false
    t.string "security_id", null: false
    t.string "segment"
    t.string "side", null: false
    t.string "status", default: "active"
    t.string "symbol"
    t.datetime "updated_at", null: false
    t.index ["instrument_id"], name: "index_paper_positions_on_instrument_id"
    t.index ["paper_order_id"], name: "index_paper_positions_on_paper_order_id"
    t.index ["security_id"], name: "index_paper_positions_on_security_id"
    t.index ["status"], name: "index_paper_positions_on_status"
  end

  create_table "paper_trades", force: :cascade do |t|
    t.decimal "brokerage", precision: 10, scale: 2, default: "0.0"
    t.datetime "created_at", null: false
    t.integer "duration_seconds"
    t.decimal "entry_price", precision: 15, scale: 2, null: false
    t.datetime "entry_time"
    t.decimal "exit_price", precision: 15, scale: 2, null: false
    t.datetime "exit_time"
    t.decimal "net_pnl", precision: 15, scale: 2, default: "0.0"
    t.bigint "paper_order_id", null: false
    t.bigint "paper_position_id", null: false
    t.decimal "pnl_percent", precision: 10, scale: 4, default: "0.0"
    t.decimal "pnl_rupees", precision: 15, scale: 2, default: "0.0"
    t.string "signal_source"
    t.datetime "updated_at", null: false
    t.index ["paper_order_id"], name: "index_paper_trades_on_paper_order_id"
    t.index ["paper_position_id"], name: "index_paper_trades_on_paper_position_id"
  end

  create_table "paper_wallets", force: :cascade do |t|
    t.decimal "available_capital", precision: 15, scale: 2, default: "0.0", null: false
    t.datetime "created_at", null: false
    t.decimal "initial_capital", precision: 15, scale: 2, default: "0.0", null: false
    t.decimal "invested_capital", precision: 15, scale: 2, default: "0.0", null: false
    t.string "mode", default: "paper", null: false
    t.decimal "total_pnl", precision: 15, scale: 2, default: "0.0", null: false
    t.datetime "updated_at", null: false
    t.index ["position_tracker_id"], name: "index_position_meta_snapshots_on_position_tracker_id", unique: true
  end

  create_table "position_trackers", force: :cascade do |t|
    t.decimal "avg_price", precision: 12, scale: 4
    t.datetime "created_at", null: false
    t.decimal "entry_price", precision: 12, scale: 4
    t.string "exit_coid"
    t.string "exit_order_id"
    t.decimal "exit_price", precision: 12, scale: 4
    t.datetime "exit_requested_at"
    t.datetime "exit_sent_at"
    t.datetime "exited_at"
    t.datetime "expansion_at"
    t.decimal "high_water_mark_pnl", precision: 12, scale: 4, default: "0.0"
    t.bigint "instrument_id", null: false
    t.decimal "last_pnl_pct", precision: 8, scale: 4
    t.decimal "last_pnl_rupees", precision: 12, scale: 4
    t.jsonb "meta", default: {}
    t.string "order_no", null: false
    t.boolean "paper", default: false, null: false
    t.integer "quantity"
    t.string "security_id", null: false
    t.string "segment"
    t.string "side"
    t.decimal "signal_confidence", precision: 8, scale: 4
    t.datetime "signal_timestamp"
    t.decimal "spread_guard_pct", precision: 8, scale: 4
    t.string "status", default: "pending", null: false
    t.string "symbol"
    t.string "trade_state"
    t.datetime "updated_at", null: false
    t.datetime "validated_at"
    t.bigint "watchable_id", null: false
    t.decimal "exit_price", precision: 12, scale: 4
    t.datetime "exited_at"
    t.string "trade_state"
    t.datetime "validated_at"
    t.datetime "expansion_at"
    t.index ["instrument_id"], name: "index_position_trackers_on_instrument_id"
    t.index ["order_no"], name: "index_position_trackers_on_order_no", unique: true
    t.index ["paper"], name: "index_position_trackers_on_paper"
    t.index ["security_id", "segment", "status"], name: "idx_trackers_on_sid_seg_status"
    t.index ["security_id", "segment"], name: "index_position_trackers_on_security_id_and_segment"
    t.index ["security_id", "status"], name: "index_position_trackers_on_security_id_and_status"
    t.index ["status", "paper"], name: "index_position_trackers_on_status_and_paper"
    t.index ["status", "security_id"], name: "index_trackers_on_status_and_security_id"
    t.index ["status"], name: "index_position_trackers_on_status"
    t.index ["watchable_type", "watchable_id"], name: "index_position_trackers_on_watchable"
  end

  create_table "public_ip_logs", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "first_seen_at"
    t.string "ip_address"
    t.string "ip_version"
    t.datetime "last_seen_at"
    t.datetime "updated_at", null: false
  end

  create_table "settings", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "key", null: false
    t.datetime "updated_at", null: false
    t.text "value"
    t.index ["key"], name: "index_settings_on_key", unique: true
  end

  create_table "solid_queue_blocked_executions", force: :cascade do |t|
    t.string "concurrency_key", null: false
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.bigint "job_id", null: false
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.index ["concurrency_key", "priority", "job_id"], name: "index_solid_queue_blocked_executions_for_release"
    t.index ["expires_at", "concurrency_key"], name: "index_solid_queue_blocked_executions_for_maintenance"
    t.index ["job_id"], name: "index_solid_queue_blocked_executions_on_job_id", unique: true
  end

  create_table "solid_queue_claimed_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.bigint "process_id"
    t.index ["job_id"], name: "index_solid_queue_claimed_executions_on_job_id", unique: true
    t.index ["process_id", "job_id"], name: "index_solid_queue_claimed_executions_on_process_id_and_job_id"
  end

  create_table "solid_queue_failed_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "error"
    t.bigint "job_id", null: false
    t.index ["job_id"], name: "index_solid_queue_failed_executions_on_job_id", unique: true
  end

  create_table "solid_queue_jobs", force: :cascade do |t|
    t.string "active_job_id"
    t.text "arguments"
    t.string "class_name", null: false
    t.string "concurrency_key"
    t.datetime "created_at", null: false
    t.datetime "finished_at"
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.datetime "scheduled_at"
    t.datetime "updated_at", null: false
    t.index ["active_job_id"], name: "index_solid_queue_jobs_on_active_job_id"
    t.index ["class_name"], name: "index_solid_queue_jobs_on_class_name"
    t.index ["finished_at"], name: "index_solid_queue_jobs_on_finished_at"
    t.index ["queue_name", "finished_at"], name: "index_solid_queue_jobs_for_filtering"
    t.index ["scheduled_at", "finished_at"], name: "index_solid_queue_jobs_for_alerting"
  end

  create_table "solid_queue_blocked_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.string "queue_name", null: false
    t.integer "priority", default: 0, null: false
    t.string "concurrency_key", null: false
    t.datetime "expires_at", null: false
    t.datetime "created_at", null: false
    t.index ["concurrency_key", "priority", "job_id"], name: "index_solid_queue_blocked_executions_for_release"
    t.index ["expires_at", "concurrency_key"], name: "index_solid_queue_blocked_executions_for_maintenance"
    t.index ["job_id"], name: "index_solid_queue_blocked_executions_on_job_id", unique: true
  end

  create_table "solid_queue_claimed_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.bigint "process_id"
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_claimed_executions_on_job_id", unique: true
    t.index ["process_id", "job_id"], name: "index_solid_queue_claimed_executions_on_process_id_and_job_id"
  end

  create_table "solid_queue_failed_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.text "error"
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_failed_executions_on_job_id", unique: true
  end

  create_table "solid_queue_jobs", force: :cascade do |t|
    t.string "queue_name", null: false
    t.string "class_name", null: false
    t.text "arguments"
    t.integer "priority", default: 0, null: false
    t.string "active_job_id"
    t.datetime "scheduled_at"
    t.datetime "finished_at"
    t.string "concurrency_key"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["active_job_id"], name: "index_solid_queue_jobs_on_active_job_id"
    t.index ["class_name"], name: "index_solid_queue_jobs_on_class_name"
    t.index ["finished_at"], name: "index_solid_queue_jobs_on_finished_at"
    t.index ["queue_name", "finished_at"], name: "index_solid_queue_jobs_for_filtering"
    t.index ["scheduled_at", "finished_at"], name: "index_solid_queue_jobs_for_alerting"
  end

  create_table "solid_queue_pauses", force: :cascade do |t|
    t.string "queue_name", null: false
    t.datetime "created_at", null: false
    t.index ["queue_name"], name: "index_solid_queue_pauses_on_queue_name", unique: true
  end

  create_table "solid_queue_processes", force: :cascade do |t|
    t.string "kind", null: false
    t.datetime "last_heartbeat_at", null: false
    t.bigint "supervisor_id"
    t.integer "pid", null: false
    t.string "hostname"
    t.text "metadata"
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.index ["last_heartbeat_at"], name: "index_solid_queue_processes_on_last_heartbeat_at"
    t.index ["name", "supervisor_id"], name: "index_solid_queue_processes_on_name_and_supervisor_id", unique: true
    t.index ["supervisor_id"], name: "index_solid_queue_processes_on_supervisor_id"
  end

  create_table "solid_queue_ready_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.string "queue_name", null: false
    t.integer "priority", default: 0, null: false
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_ready_executions_on_job_id", unique: true
    t.index ["priority", "job_id"], name: "index_solid_queue_poll_all"
    t.index ["queue_name", "priority", "job_id"], name: "index_solid_queue_poll_by_queue"
  end

  create_table "solid_queue_recurring_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.string "task_key", null: false
    t.datetime "run_at", null: false
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_recurring_executions_on_job_id", unique: true
    t.index ["task_key", "run_at"], name: "index_solid_queue_recurring_executions_on_task_key_and_run_at", unique: true
  end

  create_table "solid_queue_recurring_tasks", force: :cascade do |t|
    t.string "key", null: false
    t.string "schedule", null: false
    t.string "command", limit: 2048
    t.string "class_name"
    t.text "arguments"
    t.string "queue_name"
    t.integer "priority", default: 0
    t.boolean "static", default: true, null: false
    t.text "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_solid_queue_recurring_tasks_on_key", unique: true
    t.index ["static"], name: "index_solid_queue_recurring_tasks_on_static"
  end

  create_table "solid_queue_scheduled_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.string "queue_name", null: false
    t.integer "priority", default: 0, null: false
    t.datetime "scheduled_at", null: false
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_scheduled_executions_on_job_id", unique: true
    t.index ["scheduled_at", "priority", "job_id"], name: "index_solid_queue_dispatch_all"
  end

  create_table "solid_queue_semaphores", force: :cascade do |t|
    t.string "key", null: false
    t.integer "value", default: 1, null: false
    t.datetime "expires_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["expires_at"], name: "index_solid_queue_semaphores_on_expires_at"
    t.index ["key", "value"], name: "index_solid_queue_semaphores_on_key_and_value"
    t.index ["key"], name: "index_solid_queue_semaphores_on_key", unique: true
  end

  create_table "trade_telemetry", force: :cascade do |t|
    t.bigint "tracker_id", null: false
    t.string "index_key", null: false
    t.datetime "entry_time", null: false
    t.datetime "exit_time", null: false
    t.string "entry_tf", null: false
    t.string "htf_tf", null: false
    t.integer "bos_age_at_entry"
    t.decimal "retrace_pct", precision: 6, scale: 4
    t.integer "pullback_candles"
    t.decimal "entry_distance_r", precision: 8, scale: 4
    t.decimal "continuation_body_position", precision: 6, scale: 4
    t.integer "time_from_bos_to_entry"
    t.decimal "max_r_reached", precision: 10, scale: 4
    t.decimal "exit_r", precision: 10, scale: 4
    t.string "exit_path"
    t.decimal "pnl_rupees", precision: 12, scale: 4
    t.string "trade_state_at_exit"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["entry_time"], name: "index_trade_telemetry_on_entry_time"
    t.index ["index_key"], name: "index_trade_telemetry_on_index_key"
    t.index ["tracker_id"], name: "index_trade_telemetry_on_tracker_id", unique: true
  end

  create_table "trading_signals", force: :cascade do |t|
    t.string "index_key", null: false
    t.decimal "max_r_reached", precision: 10, scale: 4
    t.decimal "pnl_rupees", precision: 12, scale: 4
    t.integer "pullback_candles"
    t.decimal "retrace_pct", precision: 6, scale: 4
    t.integer "time_from_bos_to_entry"
    t.bigint "tracker_id", null: false
    t.string "trade_state_at_exit"
    t.datetime "updated_at", null: false
    t.index ["entry_time"], name: "index_trade_telemetry_on_entry_time"
    t.index ["index_key"], name: "index_trade_telemetry_on_index_key"
    t.index ["tracker_id"], name: "index_trade_telemetry_on_tracker_id", unique: true
  end

  create_table "trading_signals", force: :cascade do |t|
    t.decimal "adx_value", precision: 8, scale: 4
    t.datetime "candle_timestamp", null: false
    t.decimal "confidence_score", precision: 5, scale: 4
    t.datetime "created_at", null: false
    t.string "direction", null: false
    t.string "index_key", null: false
    t.jsonb "metadata", default: {}
    t.datetime "signal_timestamp", null: false
    t.decimal "supertrend_value", precision: 12, scale: 4
    t.string "timeframe", null: false
    t.datetime "updated_at", null: false
    t.index ["confidence_score"], name: "index_trading_signals_on_confidence_score"
    t.index ["direction", "signal_timestamp"], name: "index_trading_signals_on_direction_and_signal_timestamp"
    t.index ["index_key", "signal_timestamp"], name: "index_trading_signals_on_index_key_and_signal_timestamp"
    t.index ["metadata"], name: "index_trading_signals_on_metadata", using: :gin
  end

  create_table "trading_strategies", force: :cascade do |t|
    t.string "author", default: "System"
    t.jsonb "backtest_results", default: {}
    t.jsonb "checks", default: {"risk"=>"not_run", "logic"=>"not_run", "syntax"=>"not_run", "backtest"=>"not_run"}
    t.text "code", default: ""
    t.datetime "created_at", null: false
    t.text "description"
    t.jsonb "entry_rules", default: {}
    t.jsonb "exit_rules", default: {}
    t.jsonb "filters", default: {}
    t.jsonb "instruments", default: []
    t.string "name", null: false
    t.jsonb "parameters", default: []
    t.jsonb "risk_management", default: {}
    t.string "runtime", default: "Ruby"
    t.jsonb "schedule", default: {}
    t.string "slug"
    t.string "status", default: "draft"
    t.bigint "strategy_record_id"
    t.jsonb "tags", default: []
    t.string "timeframe", default: "1m"
    t.string "trade_direction", default: "both"
    t.datetime "updated_at", null: false
    t.string "version", default: "1.0.0"
    t.index ["name", "version"], name: "index_trading_strategies_on_name_and_version", unique: true
    t.index ["name"], name: "index_trading_strategies_on_name"
    t.index ["slug"], name: "index_trading_strategies_on_slug", unique: true
    t.index ["status"], name: "index_trading_strategies_on_status"
    t.index ["strategy_record_id"], name: "index_trading_strategies_on_strategy_record_id"
  end

  create_table "watchlist_items", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.integer "kind"
    t.string "label"
    t.string "security_id", null: false
    t.string "segment", null: false
    t.datetime "updated_at", null: false
    t.bigint "watchable_id"
    t.string "watchable_type"
    t.index ["segment", "security_id"], name: "index_watchlist_items_on_segment_and_security_id", unique: true
    t.index ["watchable_type", "watchable_id"], name: "index_watchlist_items_on_watchable_type_and_watchable_id"
  end

  create_table "woods_edges", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "relationship", null: false
    t.bigint "source_id", null: false
    t.bigint "target_id", null: false
    t.string "via"
    t.index ["source_id", "target_id", "relationship"], name: "idx_woods_edges_unique", unique: true
    t.index ["source_id"], name: "index_woods_edges_on_source_id"
    t.index ["target_id"], name: "index_woods_edges_on_target_id"
  end

  create_table "woods_embeddings", force: :cascade do |t|
    t.string "chunk_type"
    t.string "content_hash", null: false
    t.datetime "created_at", null: false
    t.integer "dimensions", null: false
    t.text "embedding", null: false
    t.bigint "unit_id", null: false
    t.index ["content_hash"], name: "index_woods_embeddings_on_content_hash"
    t.index ["unit_id"], name: "index_woods_embeddings_on_unit_id"
  end

  create_table "woods_units", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "file_path", null: false
    t.string "identifier", null: false
    t.json "metadata"
    t.string "namespace"
    t.text "source_code"
    t.string "source_hash"
    t.string "unit_type", null: false
    t.datetime "updated_at", null: false
    t.index ["file_path"], name: "index_woods_units_on_file_path"
    t.index ["identifier"], name: "index_woods_units_on_identifier", unique: true
    t.index ["unit_type"], name: "index_woods_units_on_unit_type"
  end

  add_foreign_key "best_indicator_params", "instruments"
  add_foreign_key "derivatives", "instruments"
  add_foreign_key "ledger_postings", "ledger_accounts"
  add_foreign_key "ledger_postings", "ledger_journal_entries"
  add_foreign_key "paper_orders", "instruments"
  add_foreign_key "paper_positions", "instruments"
  add_foreign_key "paper_positions", "paper_orders"
  add_foreign_key "paper_trades", "paper_orders"
  add_foreign_key "paper_trades", "paper_positions"
  add_foreign_key "position_meta_snapshots", "position_trackers"
  add_foreign_key "position_trackers", "instruments"
  add_foreign_key "solid_queue_blocked_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_claimed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_failed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_ready_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_recurring_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_scheduled_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "trade_telemetry", "position_trackers", column: "tracker_id"
end
