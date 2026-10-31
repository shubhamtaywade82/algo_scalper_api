# frozen_string_literal: true

# Investing domain: allocation sleeve rows per policy version (TDD §4.2).
#
# Sleeves are normalised rows rather than a JSON blob so "sum(target_pct) = 100"
# is a checkable constraint and drift SQL can aggregate by sleeve/group
# (TDD §3.3 D2). Bands themselves live on the policy's rebalancing jsonb at
# GROUP level (e.g. equity 50–60%), not per sleeve.
class CreateInvestmentPolicySleeves < ActiveRecord::Migration[8.1]
  def change
    create_table :investment_policy_sleeves do |t|
      t.references :investment_policy,
                   null: false, foreign_key: { on_delete: :cascade },
                   index: false
      t.string :sleeve_key, null: false, limit: 64
      t.string :group_key, null: false, limit: 64
      t.decimal :target_pct, precision: 7, scale: 4, null: false
      t.jsonb :instrument_filter, null: false, default: {}
      t.integer :position, null: false, default: 0
      t.timestamps
    end

    add_index :investment_policy_sleeves,
              %i[investment_policy_id sleeve_key], unique: true
    add_index :investment_policy_sleeves, :group_key
    add_check_constraint :investment_policy_sleeves,
                         "target_pct > 0 AND target_pct <= 100",
                         name: "chk_inv_sleeve_target_pct_range"
  end
end
