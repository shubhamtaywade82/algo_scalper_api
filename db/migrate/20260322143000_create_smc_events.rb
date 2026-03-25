# frozen_string_literal: true

class CreateSmcEvents < ActiveRecord::Migration[8.0]
  def change
    create_table :smc_events do |t|
      t.string :stream, null: false
      t.string :event_type, null: false
      t.string :correlation_id, null: false
      t.integer :sequence, null: false
      t.jsonb :payload, null: false, default: {}
      t.timestamps
    end

    add_index :smc_events, %i[stream created_at], name: 'index_smc_events_on_stream_and_created_at'
    add_index :smc_events, :correlation_id
    add_index :smc_events, %i[correlation_id sequence], unique: true, name: 'index_smc_events_on_correlation_id_and_sequence'
    add_index :smc_events, :payload, using: :gin, name: 'index_smc_events_on_payload'
  end
end
