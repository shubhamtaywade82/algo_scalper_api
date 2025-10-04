# frozen_string_literal: true

class AddMarketFieldsToInstruments < ActiveRecord::Migration[8.0]
  def change
    change_table :instruments, bulk: true do |t|
      t.string :exchange
      t.string :segment
      t.string :instrument_code
      t.string :instrument_type
    end

    add_index :instruments, :exchange
    add_index :instruments, :segment
    add_index :instruments, :instrument_code
  end
end
