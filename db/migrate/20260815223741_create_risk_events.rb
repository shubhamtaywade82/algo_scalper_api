# frozen_string_literal: true

class CreateRiskEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :risk_events do |t|
      t.string :event_type, null: false    # circuit_breaker_trip, daily_loss_hit, position_limit_hit, etc.
      t.string :severity, null: false, default: 'warning'  # info, warning, critical
      t.string :source, null: false        # rule name or service name
      t.text :description
      t.references :instrument, foreign_key: true
      t.references :position_tracker, foreign_key: true
      t.jsonb :context, default: {}, null: false
      t.string :action_taken              # blocked_entry, force_exit, halted_trading
      t.timestamps
    end

    add_index :risk_events, :event_type
    add_index :risk_events, :severity
    add_index :risk_events, :created_at
  end
end
