class CreateTradingSignals < ActiveRecord::Migration[8.0]
  def change
    create_table :trading_signals do |t|
      t.string :index_key, null: false
      t.string :direction, null: false
      t.decimal :confidence_score, precision: 5, scale: 4
      t.string :timeframe, null: false
      t.decimal :supertrend_value, precision: 12, scale: 4
      t.decimal :adx_value, precision: 8, scale: 4
      t.datetime :signal_timestamp, null: false
      t.datetime :candle_timestamp, null: false
      t.jsonb :metadata, default: {}

      t.timestamps
    end

    add_index :trading_signals, [ :index_key, :signal_timestamp ]
    add_index :trading_signals, [ :direction, :signal_timestamp ]
    add_index :trading_signals, :confidence_score
    add_index :trading_signals, :metadata, using: :gin
  end
end
