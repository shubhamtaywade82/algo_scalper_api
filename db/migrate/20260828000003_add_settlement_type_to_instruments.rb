# frozen_string_literal: true

class AddSettlementTypeToInstruments < ActiveRecord::Migration[8.1]
  def change
    add_column :instruments, :settlement_type, :string, default: "cash", null: false
    add_index :instruments, :settlement_type
  end
end
