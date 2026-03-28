# frozen_string_literal: true

module Risk
  module Rules
    # Premium Momentum Failure Rule - CRITICAL EXIT for intraday options buying
    #
    # PURPOSE: Kill dead option trades before theta eats them
    #
    # Logic: Track last premium high. Exit when premium does NOT make
    # progress within N minutes (configurable per index and session).
    #
    # Only fires on losing positions. Winners are handled by trailing.
    #
    # Priority: 30 (checked after structure invalidation)
    class PremiumMomentumFailureRule < BaseRule
      include SessionDetector

      PRIORITY = 30
      DEFAULT_STALL_MINUTES = 3

      def evaluate(context)
        return skip_result unless enabled?
        return skip_result unless context.active?

        tracker = context.tracker
        return skip_result unless tracker.created_at

        current_ltp = context.position.respond_to?(:current_ltp) ? context.position.current_ltp.to_f : nil
        current_ltp ||= tracker.entry_price.to_f

        meta = tracker.meta || {}
        peak = meta['peak_premium'].to_f
        last_peak_at = meta['peak_premium_at'] ? Time.zone.parse(meta['peak_premium_at']) : tracker.created_at

        if current_ltp > peak
          meta['peak_premium'] = current_ltp
          meta['peak_premium_at'] = Time.current.iso8601
          # Use update_column for performance to skip validations/callbacks
          # respond_to? check is to handle instance_doubles in tests
          tracker.update_column(:meta, meta) if tracker.respond_to?(:update_column)
          return no_action_result
        end

        return no_action_result if context.pnl_pct.to_f.positive?

        stall_minutes = resolve_stall_minutes(tracker)
        elapsed_since_peak = (Time.current - last_peak_at) / 60.0

        if elapsed_since_peak >= stall_minutes
          return exit_result(
            reason: 'PREMIUM_MOMENTUM_FAILURE',
            metadata: {
              peak: peak,
              current: current_ltp,
              elapsed_since_peak: elapsed_since_peak,
              stall_threshold: stall_minutes
            }
          )
        end

        no_action_result
      rescue StandardError => e
        Rails.logger.error("[PremiumMomentumFailureRule] Error: #{e.class} - #{e.message}")
        skip_result
      end

      def enabled?(context = nil)
        pmf_cfg = config.dig(:exits, :premium_momentum_failure) || {}
        pmf_cfg[:enabled] == true
      end

      private

      def resolve_stall_minutes(tracker)
        pmf_cfg = AlgoConfig.fetch.dig(:risk, :exits, :premium_momentum_failure) || {}

        index_key = tracker.meta&.dig('index_key')
        base = if index_key
                 pmf_cfg.dig(:index_overrides, index_key.to_sym, :stall_minutes) ||
                   pmf_cfg[:default_stall_minutes] || DEFAULT_STALL_MINUTES
               else
                 pmf_cfg[:default_stall_minutes] || DEFAULT_STALL_MINUTES
               end

        session = detect_current_session
        additive = session ? (pmf_cfg.dig(:session_overrides, session, :stall_minutes_add) || 0) : 0

        (base.to_f + additive.to_f).to_i
      rescue StandardError
        DEFAULT_STALL_MINUTES
      end
    end
  end
end
