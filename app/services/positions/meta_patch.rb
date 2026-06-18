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

        PositionTracker.where(id: tracker_id).update_all( # rubocop:disable Rails/SkipsModelValidations
          ["meta = COALESCE(meta, '{}'::jsonb) || ?::jsonb", sanitized.to_json]
        )
      end

      private

      def normalize_hash(value)
        return {} unless value.is_a?(Hash)

        value.deep_stringify_keys
      end

      def values_equal?(left, right)
        left == right
      end
    end
  end
end
