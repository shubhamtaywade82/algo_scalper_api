# frozen_string_literal: true

class AddFillReconciliationToDataQualityDailyMetrics < ActiveRecord::Migration[8.1]
  def change
    change_table :data_quality_daily_metrics, bulk: true do |t|
      t.integer :fill_reconciliation_checked_count, default: 0, null: false
      t.integer :fill_reconciliation_mismatch_count, default: 0, null: false
    end
  end
end
