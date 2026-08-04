# frozen_string_literal: true

module Risk
  module Rules
    # Time-based premium decay exit.
    #
    # Triggers when the position has been open longer than the configured threshold
    # and the current option premium has decayed below a fraction of the entry price.
    #
    # Default: elapsed > 45 minutes AND premium < 85% of entry price.
    class TimeDecayRule < BaseRule
      PRIORITY = 45

      def evaluate(context)
        return skip_result unless context.active?

        tracker = context.tracker
        elapsed = (Time.current - tracker.created_at).to_f / 60.0

        threshold_minutes = (config[:threshold_minutes] || 45).to_f
        return no_action_result if elapsed <= threshold_minutes

        current_premium = current_premium_for(tracker) || entry_premium_for(tracker)
        return no_action_result unless current_premium&.positive?

        entry_premium = entry_premium_for(tracker)
        return no_action_result unless entry_premium&.positive?

        decay_ratio = config[:decay_ratio] || 0.85
        return no_action_result unless current_premium < (entry_premium * decay_ratio.to_f)

        exit_result(
          reason: 'TIME_DECAY',
          metadata: {
            path: 'time_decay',
            elapsed_minutes: elapsed.round(1),
            threshold_minutes: threshold_minutes,
            entry_premium: entry_premium.round(4),
            current_premium: current_premium.round(4),
            decay_ratio: decay_ratio
          }
        )
      end

      def enabled?(context = nil)
        return false unless context
        cfg = context.risk_config[:time_decay] || context.risk_config.dig(:exits, :time_decay) || {}
        cfg.fetch(:enabled, false)
      end

      private

      def entry_premium_for(tracker)
        entry_price = tracker.respond_to?(:entry_price) ? tracker.entry_price : nil
        entry_price = tracker.meta&.dig('entry_price') if entry_price.nil? || entry_price.zero?
        entry_price
      rescue StandardError
        nil
      end

      def current_premium_for(tracker)
        ltp = if tracker.respond_to?(:ltp)
                tracker.ltp
              elsif tracker.respond_to?(:current_price)
                tracker.current_price
              end
        ltp || tracker.meta&.dig('current_price')
      rescue StandardError
        nil
      end
    end
  end
end
