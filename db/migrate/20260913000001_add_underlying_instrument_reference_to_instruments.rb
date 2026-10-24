# frozen_string_literal: true

# Adds the self-referential underlying link on instruments.
#
# Domain model after this change (see review 2026-09):
#   Instrument = one tradable security (equity, index, future, option)
#   underlying_instrument_id = reference from a derivative contract to its
#   underlying Instrument (NIFTY 25000 CE -> NIFTY index row).
#
# The `derivatives` table and its `instrument_id` parent link are legacy and
# will be consolidated in the follow-up migration.
class AddUnderlyingInstrumentReferenceToInstruments < ActiveRecord::Migration[8.1]
  def up
    unless column_exists?(:instruments, :underlying_instrument_id)
      add_reference :instruments, :underlying_instrument,
                    type: :bigint, index: false,
                    foreign_key: { to_table: :instruments, on_delete: :nullify }
      add_index :instruments, :underlying_instrument_id,
                name: 'index_instruments_on_underlying_instrument_id'
    end
  end

  def down
    return unless column_exists?(:instruments, :underlying_instrument_id)

    remove_index :instruments, name: 'index_instruments_on_underlying_instrument_id'
    remove_reference :instruments, :underlying_instrument, foreign_key: { to_table: :instruments }
  end
end
