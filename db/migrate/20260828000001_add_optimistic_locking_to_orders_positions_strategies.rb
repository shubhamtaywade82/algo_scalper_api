# frozen_string_literal: true

class AddOptimisticLockingToOrdersPositionsStrategies < ActiveRecord::Migration[8.1]
  def change
    add_column :order_intents, :lock_version, :integer, default: 0, null: false
    add_column :position_trackers, :lock_version, :integer, default: 0, null: false
    add_column :strategies, :lock_version, :integer, default: 0, null: false
    add_column :paper_orders, :lock_version, :integer, default: 0, null: false
  end
end
