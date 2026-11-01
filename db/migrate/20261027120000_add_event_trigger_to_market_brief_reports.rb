# frozen_string_literal: true

# Event-driven Market Brief runs record why they were started, so the commentary
# can say what changed and the live page can show it while analysis is in flight.
# The (mode, trigger, created_at) index serves the per-mode debounce and hourly cap.
class AddEventTriggerToMarketBriefReports < ActiveRecord::Migration[8.1]
  def change
    add_column :market_brief_reports, :trigger_reasons, :jsonb, null: false, default: []
    add_index :market_brief_reports, %i[mode trigger created_at]
  end
end
