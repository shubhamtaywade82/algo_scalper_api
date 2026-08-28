# frozen_string_literal: true

module Positions
  # Applies only changed top-level meta keys — never rewrites pinned config blobs.
  class MetaPatch
    IMMUTABLE_TOP_LEVEL_KEYS = %w[config_snapshot config_version].freeze

    RUNTIME_REDIS_KEYS = %w[
      highest_price lowest_price peak_trend_score peak_premium peak_premium_at
      hwm_pnl_pct telegram_notified_milestones
    ].freeze

    class << self
      def diff(before, after)
        before_h = normalize_hash(before)
        after_h = normalize_hash(after)

        after_h.each_with_object({}) do |(key, value), patch|
          patch[key] = value unless values_equal?(before_h[key], value)
        end
      end

      def apply!(tracker:, before:, after:)
        patch = diff(before, after)
        return if patch.empty?

        redis_patch = patch.slice(*RUNTIME_REDIS_KEYS)
        if redis_patch.any?
          Live::PositionRuntimeCache.instance.merge(tracker.id, redis_patch)
        end

        db_patch = patch.except(*RUNTIME_REDIS_KEYS, *IMMUTABLE_TOP_LEVEL_KEYS)
        merge_meta!(tracker.id, db_patch) if db_patch.any?
      end

      def merge_meta!(tracker_id, patch)
        sanitized = normalize_hash(patch)
        return if sanitized.empty?

        column_updates = {}
        jsonb_patch = {}

        sanitized.each do |key, val|
          if PositionTracker::PROMOTED_META_KEYS.include?(key)
            column_updates[key] = cast_value(key, val)
          else
            jsonb_patch[key] = val
          end
        end

        updates = column_updates.dup
        updates['updated_at'] = Time.current

        if jsonb_patch.any?
          sql = PositionTracker.sanitize_sql_array(["COALESCE(meta, '{}'::jsonb) || ?::jsonb", jsonb_patch.to_json])
          updates['meta'] = Arel.sql(sql)
        end

        PositionTracker.where(id: tracker_id).update_all(updates) # rubocop:disable Rails/SkipsModelValidations
      end

      private

      def normalize_hash(value)
        return {} unless value.is_a?(Hash)

        value.deep_stringify_keys
      end

      def values_equal?(left, right)
        left == right
      end

      def cast_value(key, val)
        if PositionTracker::BOOLEAN_PROMOTED_KEYS.include?(key)
          ActiveModel::Type::Boolean.new.cast(val)
        elsif %w[signal_confidence expected_value carry_roi_pct].include?(key)
          BigDecimal(val.to_s)
        elsif %w[highest_price lowest_price trailing_stop_price profit_floor_rupees
                 secured_sl_price secured_sl_rupees].include?(key)
          BigDecimal(val.to_s)
        elsif %w[profit_floor_set_at profit_zone_transitioned_at carry_marked_at signal_timestamp].include?(key)
          val.is_a?(String) ? Time.zone.parse(val) : val
        else
          val.to_s
        end
      end
    end
  end
end
