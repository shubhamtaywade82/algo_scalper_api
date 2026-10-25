# frozen_string_literal: true

# Drop dead tables: order_intents, risk_events, trade_journals.
#
# These tables backed OrderIntent, RiskEvent, and TradeJournal models that
# were introduced as part of an AASM-driven intent → risk-check → journal
# pipeline that was never wired into the live trading path. The audit
# (finding S-001) confirmed zero callers outside their own model files,
# specs, and factories. The tables have remained empty in production.
#
# This migration is intentionally irreversible:
# - The original create_* migrations remain in db/migrate/ for schema
#   archaeology (they will not re-run automatically).
# - If restoration is ever needed, restore from a pre-migration backup
#   or re-apply the original create_* migrations manually.
class DropDeadIntentRiskJournalTables < ActiveRecord::Migration[8.1]
  def up
    drop_table :order_intents, if_exists: true
    drop_table :risk_events, if_exists: true
    drop_table :trade_journals, if_exists: true
  end

  def down
    raise ActiveRecord::IrreversibleMigration,
          "Restoring order_intents/risk_events/trade_journals is not supported. " \
          "These tables backed dead code (audit S-001) and held no production data. " \
          "If you need them back, restore from a pre-migration backup or re-apply " \
          "the original create_* migrations manually."
  end
end
