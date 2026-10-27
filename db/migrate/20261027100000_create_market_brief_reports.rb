# frozen_string_literal: true

# One row per generated Market Brief. The deterministic snapshot and the AI
# interpretation are stored side by side so the dashboard and the printed PDF
# always render the same immutable facts. report_key is unique so concurrent
# generation requests for the same slot collapse onto one row (and one LLM call).
class CreateMarketBriefReports < ActiveRecord::Migration[8.1]
  def change
    create_table :market_brief_reports do |t|
      t.string :report_key, null: false
      t.date :trading_date, null: false
      t.string :mode, null: false
      t.string :trigger, null: false, default: 'manual'
      t.string :status, null: false, default: 'pending'
      t.integer :schema_version, null: false
      t.jsonb :snapshot, null: false, default: {}
      t.string :snapshot_digest
      t.datetime :snapshot_generated_at
      t.string :ai_status, null: false, default: 'pending'
      t.jsonb :ai_analysis
      t.string :ai_model
      t.string :ai_error
      t.datetime :ai_generated_at
      t.string :error
      t.timestamps
    end

    add_index :market_brief_reports, :report_key, unique: true
    add_index :market_brief_reports, %i[mode status created_at]
  end
end
