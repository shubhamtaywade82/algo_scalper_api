class AddWatchableToPositionTrackers < ActiveRecord::Migration[8.0]
  def up
    # Add polymorphic watchable association
    add_reference :position_trackers, :watchable, polymorphic: true, null: true, index: true

    # Migrate existing data: set watchable to instrument for existing records
    execute <<-SQL
      UPDATE position_trackers
      SET watchable_type = 'Instrument', watchable_id = instrument_id
      WHERE watchable_id IS NULL
    SQL

    # Make watchable required going forward (but keep instrument_id for backward compatibility during transition)
    change_column_null :position_trackers, :watchable_id, false
    change_column_null :position_trackers, :watchable_type, false
  end

  def down
    # Migrate data back: set instrument_id from watchable if it's an Instrument
    execute <<-SQL
      UPDATE position_trackers
      SET instrument_id = watchable_id
      WHERE watchable_type = 'Instrument' AND instrument_id IS NULL
    SQL

    remove_reference :position_trackers, :watchable, polymorphic: true
  end
end
