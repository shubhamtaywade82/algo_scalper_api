class AddModeToPaperDailyWallets < ActiveRecord::Migration[8.1]
  def change
    # Default backfills existing rows as 'paper' (metadata-only default on Postgres 11+,
    # no table rewrite) — this table was paper-only until Ledger::DailyCloseJob gained a
    # live-mode path. EquityCurveController must filter on this once live rows exist.
    add_column :paper_daily_wallets, :mode, :string, default: 'paper', null: false

    remove_index :paper_daily_wallets, :trading_date, unique: true
    add_index :paper_daily_wallets, %i[trading_date mode], unique: true
  end
end
