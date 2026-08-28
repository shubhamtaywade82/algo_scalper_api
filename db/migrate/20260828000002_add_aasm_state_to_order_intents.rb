# frozen_string_literal: true

class AddAasmStateToOrderIntents < ActiveRecord::Migration[8.1]
  def change
    add_column :order_intents, :aasm_state, :string, default: "created", null: false
    add_index :order_intents, :aasm_state
  end
end
