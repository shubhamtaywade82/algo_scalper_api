class CreateDataQualityDailyMetrics < ActiveRecord::Migration[8.1]
  def change
    create_table :data_quality_daily_metrics do |t|
      t.date :trading_date, null: false
      t.integer :missing_candle_count, default: 0, null: false
      t.decimal :candle_alignment_accuracy_pct, precision: 8, scale: 4
      t.decimal :tick_staleness_rate_pct, precision: 8, scale: 4
      t.decimal :instrument_mapping_accuracy_pct, precision: 8, scale: 4
      t.integer :expired_instrument_count, default: 0, null: false
      t.jsonb :meta, default: {}, null: false

      t.timestamps
    end

    add_index :data_quality_daily_metrics, :trading_date, unique: true
  end
end
