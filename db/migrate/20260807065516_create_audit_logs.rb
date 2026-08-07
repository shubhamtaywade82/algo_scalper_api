class CreateAuditLogs < ActiveRecord::Migration[8.1]
  def change
    create_table :audit_logs do |t|
      t.string :event_type, null: false
      t.string :actor
      t.jsonb :metadata, default: {}, null: false

      t.timestamps
    end

    add_index :audit_logs, :event_type
    add_index :audit_logs, :created_at
  end
end
