# frozen_string_literal: true

class CreateResearchOptionBars < ActiveRecord::Migration[7.1]
  def change
    create_table :research_option_bars do |t|
      t.references :research_raw_fetch, foreign_key: true
      t.string   :underlying_symbol, null: false
      t.string   :exchange_segment,  null: false
      t.string   :instrument,        null: false, default: "OPTIDX"
      t.string   :expiry_flag,       null: false # WEEK | MONTH
      t.string   :option_type,       null: false # CE | PE
      t.string   :strike_label,      null: false # ATM, ITM1, OTM2, ...
      t.decimal  :actual_strike,     precision: 12, scale: 4
      t.string   :interval,          null: false, default: "5"
      t.datetime :ts,                null: false
      t.decimal  :open,  precision: 12, scale: 4
      t.decimal  :high,  precision: 12, scale: 4
      t.decimal  :low,   precision: 12, scale: 4
      t.decimal  :close, precision: 12, scale: 4
      t.bigint   :volume, default: 0
      t.bigint   :oi
      t.decimal  :iv, precision: 10, scale: 4
      t.decimal  :spot, precision: 12, scale: 4
      t.string   :source, null: false, default: "rolling_option"

      t.timestamps
    end

    add_index :research_option_bars,
              [:underlying_symbol, :expiry_flag, :option_type, :strike_label, :interval, :ts],
              unique: true,
              name: "index_research_option_bars_on_contract_and_ts"
  end
end
