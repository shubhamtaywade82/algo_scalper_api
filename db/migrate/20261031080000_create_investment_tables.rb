# frozen_string_literal: true

# Investing domain tables — full DDL rationale in docs/investing/TECHNICAL_DESIGN.md §4.
class CreateInvestmentTables < ActiveRecord::Migration[8.1]
  def change
    # ---------------------------------------------------------------- portfolios
    create_table :investment_portfolios do |t|
      t.string :name, null: false
      t.string :mode, null: false, default: 'paper' # paper | live
      t.string :base_currency, null: false, default: 'INR'
      t.decimal :cash_balance, precision: 18, scale: 2, null: false, default: 0
      t.decimal :invested_amount, precision: 18, scale: 2, null: false, default: 0
      t.datetime :active_policy_changed_at
      t.jsonb :meta, null: false, default: {}
      t.timestamps
    end
    add_index :investment_portfolios, :mode
    add_index :investment_portfolios, :name, unique: true

    # ------------------------------------------------------------------- policy
    create_table :investment_policies do |t|
      t.references :investment_portfolio, null: false, foreign_key: true
      t.string :mandate_version, null: false                     # e.g. balanced_v1
      t.string :status, null: false, default: 'draft'            # draft|active|retired
      t.jsonb :constraints, null: false, default: {}
      t.decimal :rebalance_band_min_pct, precision: 8, scale: 4, null: false, default: 50
      t.decimal :rebalance_band_max_pct, precision: 8, scale: 4, null: false, default: 60
      t.date :effective_from
      t.date :effective_to
      t.timestamps
    end
    add_index :investment_policies, %i[investment_portfolio_id status]
    # exactly one active policy per portfolio (partial unique index)
    add_index :investment_policies, :investment_portfolio_id,
              unique: true,
              where: "status = 'active'",
              name: 'idx_investment_policies_one_active_per_portfolio'

    # ------------------------------------------------------------------ sleeves
    create_table :allocation_sleeves do |t|
      t.references :investment_policy, null: false, foreign_key: true
      t.string :sleeve_key, null: false        # stable slug, e.g. large_cap_core
      t.string :sleeve_name, null: false       # display, e.g. "Large-Cap Core (Nifty 100)"
      t.string :asset_class, null: false       # equity|debt|gold|cash|reit|invit
      t.decimal :target_weight_pct, precision: 8, scale: 4, null: false
      t.jsonb :instruments, null: false, default: [] # ISIN allowlist (advisory)
      t.integer :display_order, null: false, default: 0
      t.timestamps
    end
    add_index :allocation_sleeves, %i[investment_policy_id sleeve_key], unique: true

    # ----------------------------------------------------------------- holdings
    create_table :investment_holdings do |t|
      t.references :investment_portfolio, null: false, foreign_key: true
      t.references :instrument, null: false, foreign_key: true
      t.string :sleeve_key, null: false
      t.decimal :quantity, precision: 18, scale: 4, null: false, default: 0
      t.decimal :available_quantity, precision: 18, scale: 4, null: false, default: 0
      t.decimal :t1_quantity, precision: 18, scale: 4, null: false, default: 0
      t.decimal :average_cost_price, precision: 18, scale: 4, null: false, default: 0
      t.decimal :last_price, precision: 18, scale: 4, null: false, default: 0
      t.boolean :is_illiquid, null: false, default: false
      t.timestamps
    end
    add_index :investment_holdings,
              %i[investment_portfolio_id instrument_id], unique: true
    add_index :investment_holdings, %i[investment_portfolio_id sleeve_key]

    # ------------------------------------------------------- rebalances
    # (before orders: investment_orders carries an FK to it)
    create_table :investment_rebalances do |t|
      t.references :investment_portfolio, null: false, foreign_key: true
      t.references :investment_policy, null: false, foreign_key: true
      t.string :trigger, null: false # drift|schedule|manual|cash_infusion
      t.jsonb :proposed_trades, null: false, default: []
      t.jsonb :drift_report, null: false, default: {}
      t.string :status, null: false, default: 'proposed'
      # proposed|approved|rejected|executed|cancelled
      t.bigint :approved_by
      t.datetime :approved_at
      t.timestamps
    end
    add_index :investment_rebalances, %i[investment_portfolio_id status]

    # ------------------------------------------------------------------- orders
    create_table :investment_orders do |t|
      t.references :investment_portfolio, null: false, foreign_key: true
      t.references :investment_rebalance, foreign_key: true
      t.references :instrument, null: false, foreign_key: true
      t.string :side, null: false                            # buy|sell
      t.string :order_type, null: false, default: 'market'   # market|limit
      t.decimal :quantity, precision: 18, scale: 4, null: false
      t.decimal :limit_price, precision: 18, scale: 4
      t.string :product_type, null: false, default: 'CNC'
      t.string :status, null: false, default: 'draft'
      t.string :correlation_id, null: false
      t.string :broker_order_id
      t.decimal :filled_quantity, precision: 18, scale: 4, null: false, default: 0
      t.decimal :average_fill_price, precision: 18, scale: 4, null: false, default: 0
      t.string :rejection_reason
      t.jsonb :broker_payload, null: false, default: {}
      t.timestamps
    end
    add_index :investment_orders, :correlation_id, unique: true
    add_index :investment_orders, %i[investment_portfolio_id status]
    add_index :investment_orders, :broker_order_id
    add_index :investment_orders, :updated_at

    # --------------------------------------------------------------------- lots
    # (after orders: FK to investment_orders)
    create_table :investment_lots do |t|
      t.references :investment_holding, null: false, foreign_key: true
      t.references :investment_order, foreign_key: true
      t.decimal :quantity, precision: 18, scale: 4, null: false
      t.decimal :remaining_quantity, precision: 18, scale: 4, null: false
      t.decimal :buy_price, precision: 18, scale: 4, null: false
      t.date :acquired_on, null: false
      t.string :lot_source, null: false, default: 'order' # order|transfer|corporate_action
      t.timestamps
    end
    add_index :investment_lots, %i[investment_holding_id acquired_on] # FIFO scan

    # -------------------------------------------------------------------- fills
    create_table :investment_fills do |t|
      t.references :investment_order, null: false, foreign_key: true
      t.string :broker_trade_id, null: false
      t.decimal :quantity, precision: 18, scale: 4, null: false
      t.decimal :price, precision: 18, scale: 4, null: false
      t.jsonb :broker_payload, null: false, default: {}
      t.timestamps
    end
    add_index :investment_fills, :broker_trade_id, unique: true
    # NOTE: no explicit add_index on investment_order_id — t.references
    # already creates index_investment_fills_on_investment_order_id

    # ------------------------------------------------------------ transactions
    create_table :investment_transactions do |t|
      t.references :investment_portfolio, null: false, foreign_key: true
      t.references :investment_order, foreign_key: true
      t.string :txn_type, null: false
      # buy|sell|dividend|deposit|withdrawal|charge|corporate_action
      t.decimal :amount, precision: 18, scale: 2, null: false
      t.decimal :quantity_delta, precision: 18, scale: 4, null: false, default: 0
      t.string :external_ref
      t.jsonb :meta, null: false, default: {}
      t.timestamps
    end
    add_index :investment_transactions, %i[investment_portfolio_id created_at]

    # --------------------------------------------------------------- snapshots
    create_table :investment_snapshots do |t|
      t.references :investment_portfolio, null: false, foreign_key: true
      t.date :as_of_date, null: false
      t.decimal :total_value, precision: 18, scale: 2, null: false
      t.decimal :cash_balance, precision: 18, scale: 2, null: false
      t.decimal :invested_value, precision: 18, scale: 2, null: false
      t.jsonb :sleeve_weights, null: false, default: {}
      t.decimal :xirr, precision: 10, scale: 6
      t.timestamps
    end
    add_index :investment_snapshots, %i[investment_portfolio_id as_of_date],
              unique: true
  end
end
