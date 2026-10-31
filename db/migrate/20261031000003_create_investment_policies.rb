# frozen_string_literal: true

# Investing domain: versioned, immutable investment mandates (TDD §4.2).
#
# A policy row is never edited once active — a change installs a new version
# and supersedes the previous row with effective_until (TDD §3.3 D1). Drift
# analysis and rebalance proposals pin the policy_id they were computed
# against so historical proposals stay explainable.
class CreateInvestmentPolicies < ActiveRecord::Migration[8.1]
  def change
    create_table :investment_policies do |t|
      t.references :investment_portfolio,
                   null: false, foreign_key: { on_delete: :cascade },
                   index: false
      t.integer :version, null: false, default: 1
      t.string :status, null: false, default: "draft"
      t.date :effective_from, null: false
      t.date :effective_until
      t.jsonb :constraints, null: false, default: {}
      t.jsonb :rebalancing, null: false, default: {}
      t.jsonb :deployment, null: false, default: {}
      t.string :mandate_key
      t.timestamps
    end

    add_index :investment_policies,
              %i[investment_portfolio_id version], unique: true
    add_index :investment_policies, :status
    # Exactly one active policy per portfolio (TDD §3.3 D1, DB-enforced)
    add_index :investment_policies, :investment_portfolio_id,
              unique: true, where: "status = 'active'",
              name: "idx_inv_policies_one_active_per_portfolio"
  end
end
