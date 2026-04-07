# frozen_string_literal: true

# Adds performance-critical indexes to position_trackers:
#
# 1. Expression index on `meta->>'index_key'` — used in analytics, auditor,
#    and dashboard queries that filter by index_key from the JSONB meta column.
#    Using a btree expression index avoids a full table scan on every such query.
#
# 2. `exited_at` index — used in all historical PnL queries and date-range
#    filters (e.g., PositionsController#closed_positions, Auditor#exited_scope).
#    Without this, every date-range query performs a sequential scan.
class AddPerformanceIndexesToPositionTrackers < ActiveRecord::Migration[7.2]
  def change
    # Expression index for JSONB key — enables fast WHERE meta->>'index_key' = ? queries
    add_index :position_trackers,
              "((meta->>'index_key'))",
              name: "index_position_trackers_on_meta_index_key",
              if_not_exists: true

    # Composite index on (exited_at, status) — covers the most common query pattern:
    # WHERE status = 'exited' AND exited_at >= ? ORDER BY exited_at DESC
    add_index :position_trackers,
              %i[exited_at status],
              name: "index_position_trackers_on_exited_at_and_status",
              if_not_exists: true
  end
end
