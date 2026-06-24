# frozen_string_literal: true

class BackfillPositionMetaColumnsAndExtractSnapshots < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  PROMOTED_KEYS = %w[
    breakeven_locked trailing_stop_price index_key direction entry_path entry_strategy
    exit_path exit_reason highest_price lowest_price be_set profit_floor_rupees
    profit_floor_set_at profit_zone_state profit_zone_transitioned_at secured_sl_price
    secured_sl_rupees carry_mode carry_marked_at carry_roi_pct alpha_source
    signal_confidence expected_value signal_timestamp client_order_id
  ].freeze

  def up
    say "Promoting scalar meta fields to columns on position_trackers..."
    total = PositionTracker.count
    processed = 0

    PositionTracker.find_each(batch_size: 200) do |tracker|
      meta = tracker.meta
      next unless meta.is_a?(Hash)

      updates = {}
      PROMOTED_KEYS.each do |key|
        val = meta[key]
        next if val.nil?

        column = key
        updates[column] = case column
                          when 'breakeven_locked', 'be_set'
                            ActiveRecord::Type::Boolean.new.cast(val)
                          when 'signal_confidence', 'expected_value', 'carry_roi_pct'
                            BigDecimal(val.to_s)
                          when 'highest_price', 'lowest_price', 'trailing_stop_price',
                               'profit_floor_rupees', 'secured_sl_price', 'secured_sl_rupees'
                            BigDecimal(val.to_s)
                          when 'profit_floor_set_at', 'profit_zone_transitioned_at',
                               'carry_marked_at', 'signal_timestamp'
                            val.is_a?(String) ? Time.zone.parse(val) : val
                          else
                            val.to_s
                          end
      end

      next if updates.empty?

      slim_meta = meta.except(*PROMOTED_KEYS)
      PositionTracker.where(id: tracker.id).update_all(
        updates.merge(
          'meta' => slim_meta,
          'updated_at' => Time.current
        )
      )

      # Extract config_snapshot snapshot if present
      snap = meta['config_snapshot']
      next unless snap.is_a?(Hash) && snap.present?

      version = meta['config_version'] || {}
      PositionMetaSnapshot.create!(
        position_tracker: tracker,
        config_version_hash: version['hash'].to_s,
        config_change_log_id: version['change_log_id'],
        config_snapshot: snap,
        entry_at: meta['entry_at']
      )

      processed += 1
      say "#{processed}/#{total} processed", true if processed % 500 == 0
    end

    say "Backfill complete: #{processed} trackers promoted, snapshots extracted."
  end

  def down
    say "Rollback: this migration is not automatically reversible. Manually restore meta from columns and drop snapshots if needed."
  end
end
