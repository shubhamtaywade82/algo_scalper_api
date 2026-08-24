# frozen_string_literal: true

class AddPrdColumnsToInstruments < ActiveRecord::Migration[8.1]
  def change
    add_column :instruments, :custom_symbol, :string
    add_column :instruments, :contract_multiplier, :decimal, precision: 10, scale: 4, default: 1.0
    add_column :instruments, :active, :boolean, default: true, null: false
    add_column :instruments, :tradable, :boolean, default: true, null: false

    add_index :instruments, :active
    add_index :instruments, :tradable
  end
end
