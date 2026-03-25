# frozen_string_literal: true

module Entries
  module Guards
    class MiddayQualityGuard
      OPENING_START = '09:15'
      OPENING_END = '10:30'
      MIDDAY_START = '10:31'
      DEFAULT_BLOCK_AFTER = '15:00'

      class << self
        include BaseGuard

        def call(context)
          return PASS unless config_enabled?
          return { blocked: "no new trades after #{block_after_time}" } if blocked_after_cutoff?
          return PASS if opening_window?
          return PASS unless midday_or_later_before_cutoff?
          return PASS if quality_passed?(context)

          { blocked: "midday quality gate blocked for #{context.dig(:index_cfg, :key)}" }
        end

        private

        def config
          AlgoConfig.fetch[:midday_guard] || {}
        rescue StandardError
          {}
        end

        def config_enabled?
          config[:enabled] == true
        end

        def block_after_time
          config[:block_after_time].presence || DEFAULT_BLOCK_AFTER
        end

        def current_ist_time
          Time.current.in_time_zone('Asia/Kolkata').strftime('%H:%M')
        end

        def opening_window?
          in_range?(OPENING_START, OPENING_END)
        end

        def midday_or_later_before_cutoff?
          in_range?(MIDDAY_START, block_after_time)
        end

        def blocked_after_cutoff?
          current_ist_time >= block_after_time
        end

        def in_range?(start_time, end_time)
          time = current_ist_time
          time.between?(start_time, end_time)
        end

        def quality_passed?(context)
          confidence_ok?(context) && adx_ok?(context)
        end

        def confidence_ok?(context)
          threshold = config[:min_confidence]
          return true if threshold.nil?

          value = confidence_value(context)
          return true if value.nil?

          value >= threshold.to_f
        end

        def adx_ok?(context)
          threshold = config[:min_adx]
          return true if threshold.nil?

          value = adx_value(context)
          return true if value.nil?

          value >= threshold.to_f
        end

        def confidence_value(context)
          metadata = context[:entry_metadata] || {}
          candidate = metadata[:market_context_conviction] || metadata[:regime_confidence] || metadata[:ta_confidence]
          normalize_confidence(candidate)
        end

        def normalize_confidence(value)
          return nil if value.nil?

          numeric = value.to_f
          numeric > 1.0 ? (numeric / 100.0) : numeric
        end

        def adx_value(context)
          metadata = context[:entry_metadata] || {}
          context.dig(:pick, :adx_value) || metadata[:adx_value]
        end
      end
    end
  end
end
