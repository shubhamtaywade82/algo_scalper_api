# frozen_string_literal: true

# Follow-up to BackfillPositionMetaColumnsAndExtractSnapshots (20260625000002).
#
# That migration promoted meta['index_key']/meta['entry_strategy'] into their real
# columns as a one-time fix, but store_accessor :meta, ..., :index_key, :entry_strategy
# on PositionTracker kept shadowing every subsequent write — every position created
# since then wrote index_key/entry_strategy into `meta` only, leaving the real
# (indexed) columns empty again. That silently broke every SQL `.where(index_key: ...)`
# / `.where(entry_strategy: ...)` query, including the live Entries::Guards::
# DirectionConflictGuard and OptionsBuying::PerformanceDb.
#
# This migration re-runs the same promotion for the two fields that are actually
# queried via SQL, and the accompanying code change removes the store_accessor
# shadow + adds index_key/entry_strategy as real create! kwargs in EntryGuard so
# the drift doesn't reaccumulate.
class BackfillIndexKeyAndEntryStrategyColumns < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def up
    say_with_time('Promoting meta[index_key]/meta[entry_strategy] to their columns...') do
      count = 0

      PositionTracker.find_in_batches(batch_size: 200) do |batch|
        batch.each do |tracker|
          meta = tracker.meta || {}
          updates = {}

          updates['index_key'] = meta['index_key'] if tracker.read_attribute(:index_key).nil? && meta['index_key'].present?
          updates['entry_strategy'] = meta['entry_strategy'] if tracker.read_attribute(:entry_strategy).nil? && meta['entry_strategy'].present?

          next if updates.empty?

          # rubocop:disable Rails/SkipsModelValidations
          tracker.update_columns(updates.merge('updated_at' => Time.current))
          # rubocop:enable Rails/SkipsModelValidations
          count += 1
        end
      end

      say("Total trackers backfilled: #{count}")
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
