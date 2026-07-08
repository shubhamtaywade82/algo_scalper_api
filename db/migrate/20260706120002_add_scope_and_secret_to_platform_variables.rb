# frozen_string_literal: true

class AddScopeAndSecretToPlatformVariables < ActiveRecord::Migration[7.1]
  def change
    add_column :platform_variables, :scope, :string, null: false, default: "global"
    add_column :platform_variables, :strategy_id, :bigint
    add_column :platform_variables, :secret, :boolean, null: false, default: false

    add_index :platform_variables, %i[scope strategy_id key], unique: true,
              name: "idx_platform_variables_on_scope_strategy_key"
  end
end
