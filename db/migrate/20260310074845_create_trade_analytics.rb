class CreateTradeAnalytics < ActiveRecord::Migration[8.0]
  def change
    create_table :trade_analytics do |t|
      t.references :position_tracker, null: false, foreign_key: true
      t.string :symbol
      t.decimal :entry_price
      t.decimal :exit_price
      t.decimal :max_favorable_excursion
      t.decimal :max_adverse_excursion
      t.integer :duration_seconds
      t.decimal :volatility
      t.string :strategy
      t.string :exit_reason

      t.timestamps
    end
  end
end
