# frozen_string_literal: true

class CreateOptionsBuyingSignalEvents < ActiveRecord::Migration[8.0]
  def change
    create_table :options_buying_signal_events do |t|
      t.string :index_key, null: false
      t.string :security_id
      t.string :event_type, null: false
      t.jsonb :metadata, null: false, default: {}
      t.datetime :occurred_at, null: false
      t.timestamps
    end

    add_index :options_buying_signal_events, :index_key
    add_index :options_buying_signal_events, :event_type
    add_index :options_buying_signal_events, :occurred_at
    add_index :options_buying_signal_events, :metadata, using: :gin
  end
end
