class CreateInstruments < ActiveRecord::Migration[8.0]
  def change
    create_table :instruments do |t|
      t.string :exchange, null: false
      t.string :segment, null: false
      t.string :security_id, null: false
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
      t.decimal :strike_price, precision: 15, scale: 5
      t.string :option_type
      t.decimal :tick_size
      t.string :expiry_flag
      t.string :bracket_flag
      t.string :cover_flag
      t.string :asm_gsm_flag
      t.string :asm_gsm_category
      t.string :buy_sell_indicator
      t.decimal :buy_co_min_margin_per, precision: 8, scale: 2
      t.decimal :sell_co_min_margin_per, precision: 8, scale: 2
      t.decimal :buy_co_sl_range_max_perc, precision: 8, scale: 2
      t.decimal :sell_co_sl_range_max_perc, precision: 8, scale: 2
      t.decimal :buy_co_sl_range_min_perc, precision: 8, scale: 2
      t.decimal :sell_co_sl_range_min_perc, precision: 8, scale: 2
      t.decimal :buy_bo_min_margin_per, precision: 8, scale: 2
      t.decimal :sell_bo_min_margin_per, precision: 8, scale: 2
      t.decimal :buy_bo_sl_range_max_perc, precision: 8, scale: 2
      t.decimal :sell_bo_sl_range_max_perc, precision: 8, scale: 2
      t.decimal :buy_bo_sl_range_min_perc, precision: 8, scale: 2
      t.decimal :sell_bo_sl_min_range, precision: 8, scale: 2
      t.decimal :buy_bo_profit_range_max_perc, precision: 8, scale: 2
      t.decimal :sell_bo_profit_range_max_perc, precision: 8, scale: 2
      t.decimal :buy_bo_profit_range_min_perc, precision: 8, scale: 2
      t.decimal :sell_bo_profit_range_min_perc, precision: 8, scale: 2
      t.decimal :mtf_leverage, precision: 8, scale: 2

      t.timestamps
    end

    add_index :instruments, %i[security_id symbol_name exchange segment], unique: true, name: 'index_instruments_unique'
    add_index :instruments, :instrument_code
    add_index :instruments, :symbol_name
    add_index :instruments, %i[underlying_symbol expiry_date], where: 'underlying_symbol IS NOT NULL'
  end
end
