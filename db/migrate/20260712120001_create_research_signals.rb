# frozen_string_literal: true

class CreateResearchSignals < ActiveRecord::Migration[7.1]
  def change
    create_table :research_signals do |t|
      t.string   :strategy_name
      t.string   :underlying_symbol, null: false
      t.datetime :signal_timestamp,  null: false
      t.string   :direction,         null: false # bullish | bearish | no_trade
      t.decimal  :spot_price,        precision: 12, scale: 4, null: false
      t.decimal  :confidence,        precision: 6, scale: 3
      t.string   :source,           null: false, default: "manual"
      t.string   :source_type
      t.bigint   :source_id
      t.jsonb    :reason,           null: false, default: {}
      t.jsonb    :metadata,         null: false, default: {}

      t.timestamps
    end

    add_index :research_signals, [:underlying_symbol, :signal_timestamp], name: "index_research_signals_on_symbol_and_ts"
    add_index :research_signals, [:source_type, :source_id]
  end
end
