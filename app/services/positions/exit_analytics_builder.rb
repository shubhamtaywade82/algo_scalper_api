# frozen_string_literal: true

module Positions
  # Stamps post-trade analytics on position meta at exit for calibration and tuning.
  class ExitAnalyticsBuilder
    class << self
      def build(tracker:, exit_price: nil)
        {
          exit_analytics_at: Time.current.iso8601,
          vix_at_exit: Market::VixGate.current_ltp,
          spread_pct_at_exit: spread_pct_at(tracker: tracker, exit_price: exit_price),
          dte_at_exit: dte_at_exit_for(tracker),
          regime_at_exit: regime_label,
          tier_at_exit: signal_tier,
          exit_path: exit_path_for(tracker)
        }.compact
      end

      private

      def spread_pct_at(tracker:, exit_price:)
        ltp = exit_price || ltp_from_cache(tracker)
        ltp = ltp.to_f
        return nil unless ltp.positive?

        tick = Live::TickQuery.for_security(
          segment: tracker.segment,
          security_id: tracker.security_id
        )
        return nil unless tick

        bid = tick.bid.to_f
        ask = tick.ask.to_f
        return nil unless bid.positive? && ask.positive? && ask >= bid

        ((ask - bid) / ltp).round(6)
      rescue StandardError => e
        Rails.logger.warn("[ExitAnalyticsBuilder] spread_pct_at #{e.class} - #{e.message}")
        nil
      end

      def ltp_from_cache(tracker)
        Live::TickQuery.for_security(
          segment: tracker.segment,
          security_id: tracker.security_id
        )&.ltp
      end

      def dte_at_exit_for(tracker)
        expiry = tracker.respond_to?(:expiry_date) ? tracker.expiry_date : nil
        return nil if expiry.blank?

        (expiry.to_date - Time.zone.today).to_i
      rescue ArgumentError
        nil
      end

      def regime_label
        Live::TimeRegimeService.instance.current_regime.to_s
      rescue StandardError
        nil
      end

      def signal_tier
        AlgoConfig.fetch.dig(:signals, :signal_tier)&.to_s
      rescue StandardError
        nil
      end

      def exit_path_for(tracker)
        tracker.exit_path.presence || tracker.exit_reason.to_s.split(/\s+/).first.presence
      end
    end
  end
end