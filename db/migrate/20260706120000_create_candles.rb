# frozen_string_literal: true

class CreateCandles < ActiveRecord::Migration[7.1]
  def change
    create_table :candles do |t|
      t.string   :instrument_key,   null: false
      t.string   :exchange_segment, null: false
      t.string   :security_id,      null: false
      t.string   :timeframe,        null: false, default: "1m"
      t.datetime :ts,               null: false
      t.decimal  :open,  precision: 12, scale: 4, null: false
      t.decimal  :high,  precision: 12, scale: 4, null: false
      t.decimal  :low,   precision: 12, scale: 4, null: false
      t.decimal  :close, precision: 12, scale: 4, null: false
      t.bigint   :volume, default: 0
      t.bigint   :oi
      t.string   :source, null: false, default: "live"

      t.timestamps
    end

    add_index :candles, [:instrument_key, :timeframe, :ts], unique: true, name: "index_candles_on_key_timeframe_ts"
    add_index :candles, [:security_id, :timeframe, :ts], name: "index_candles_on_security_timeframe_ts"
  end
end
