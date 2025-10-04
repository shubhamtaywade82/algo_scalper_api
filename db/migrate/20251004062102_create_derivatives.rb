class CreateDerivatives < ActiveRecord::Migration[8.0]
  def change
    create_table :derivatives do |t|
      t.references :instrument, null: false, foreign_key: true
      t.string :exchange
      t.string :segment
      t.string :security_id
      t.string :isin
      t.string :instrument_code
      t.string :underlying_security_id
      t.string :underlying_symbol
      t.string :symbol_name
      t.string :display_name
      t.string :instrument_type
      t.string :series
      t.integer :lot_size
      t.date :expiry_date
      t.decimal :strike_price
      t.string :option_type
      t.decimal :tick_size
      t.string :expiry_flag
      t.string :bracket_flag
      t.string :cover_flag
      t.string :asm_gsm_flag
      t.string :asm_gsm_category
      t.string :buy_sell_indicator
      t.decimal :buy_co_min_margin_per
      t.decimal :sell_co_min_margin_per
      t.decimal :buy_co_sl_range_max_perc
      t.decimal :sell_co_sl_range_max_perc
      t.decimal :buy_co_sl_range_min_perc
      t.decimal :sell_co_sl_range_min_perc
      t.decimal :buy_bo_min_margin_per
      t.decimal :sell_bo_min_margin_per
      t.decimal :buy_bo_sl_range_max_perc
      t.decimal :sell_bo_sl_range_max_perc
      t.decimal :buy_bo_sl_range_min_perc
      t.decimal :sell_bo_sl_min_range
      t.decimal :buy_bo_profit_range_max_perc
      t.decimal :sell_bo_profit_range_max_perc
      t.decimal :buy_bo_profit_range_min_perc
      t.decimal :sell_bo_profit_range_min_perc
      t.decimal :mtf_leverage

      t.timestamps
    end

    add_index :derivatives, %i[security_id symbol_name exchange segment], unique: true, name: 'index_derivatives_unique'
    add_index :derivatives, :instrument_code
    add_index :derivatives, :symbol_name
    add_index :derivatives, %i[underlying_symbol expiry_date], where: 'underlying_symbol IS NOT NULL'
  end
end
