class CreateAlphaEngineTables < ActiveRecord::Migration[8.1]
  def change
    create_table :iv_snapshots do |t|
      t.string :index_key, null: false
      t.date :snapshot_date, null: false
      t.decimal :implied_volatility, precision: 8, scale: 4
      t.decimal :strike_price, precision: 15, scale: 5
      t.string :option_type, limit: 2
      t.decimal :underlying_ltp, precision: 15, scale: 5
      t.timestamps

      t.index [:index_key, :snapshot_date]
      t.index [:index_key, :snapshot_date, :strike_price, :option_type], unique: true, name: 'index_iv_snapshots_unique'
    end

    create_table :alpha_signals do |t|
      t.string :index_key, null: false
      t.string :direction, null: false
      t.string :alpha_source, null: false
      t.decimal :strike_price, precision: 15, scale: 5
      t.date :expiry_date
      t.decimal :confidence, precision: 5, scale: 4
      t.decimal :expected_value, precision: 15, scale: 5
      t.string :status, default: 'pending' # pending, executed, rejected, expired
      t.string :order_id
      t.text :iv_context
      t.timestamps

      t.index [:index_key, :alpha_source, :created_at]
      t.index [:status, :created_at]
    end
  end
end
