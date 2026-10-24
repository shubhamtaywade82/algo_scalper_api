# frozen_string_literal: true

module Positions
  class MetaUpdater < ApplicationService
    def initialize(tracker:)
      @tracker = tracker
    end

    def update!
      tracker.with_lock do
        tracker.reload
        updated_meta = yield(tracker.meta.is_a?(Hash) ? tracker.meta.dup : {})

        scalar_updates = {}
        PositionTracker::PROMOTED_META_KEYS.each do |key|
          next unless updated_meta.key?(key)
          scalar_updates[key] = cast_value(key, updated_meta[key])
          updated_meta.except!(key)
        end

        tracker.update!(meta: updated_meta)
        tracker.update_columns(scalar_updates) if scalar_updates.any? # rubocop:disable Rails/SkipsModelValidations
      end
    end

    private

    attr_reader :tracker

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
