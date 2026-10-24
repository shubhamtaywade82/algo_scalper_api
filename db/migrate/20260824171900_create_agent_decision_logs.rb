# frozen_string_literal: true

class CreateAgentDecisionLogs < ActiveRecord::Migration[8.1]
  def change
    create_table :agent_decision_logs do |t|
      t.string :agent_name, null: false
      t.string :authority_level, null: false, default: 'advisor'
      t.string :decision_type, null: false
      t.jsonb :input_context, default: {}
      t.jsonb :output, default: {}
      t.decimal :confidence, precision: 5, scale: 4
      t.string :published_event
      t.text :error
      t.timestamps
    end

    add_index :agent_decision_logs, :agent_name
    add_index :agent_decision_logs, :created_at
    add_index :agent_decision_logs, %i[agent_name created_at]
  end
end
