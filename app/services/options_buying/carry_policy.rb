# frozen_string_literal: true

module OptionsBuying
  class CarryPolicy
    class << self
      def carry_allowed?(index_key:, expiry_date: nil)
        return false unless Mode.positional_active?
        return false if Mode.config.dig(:positional, :require_carry_allowed) == false

        expiry = expiry_date || resolve_expiry(index_key)
        return false unless expiry

        dte = (expiry - Time.zone.today).to_i
        dte >= 1
      rescue StandardError => e
        Rails.logger.warn("[CarryPolicy] #{e.class} - #{e.message}")
        false
      end

      def expiry_day?(index_key:, expiry_date: nil)
        expiry = expiry_date || resolve_expiry(index_key)
        return false unless expiry

        expiry == Time.zone.today
      rescue StandardError
        false
      end

      # Minimum realized-on-premium ROI (DECIMAL, e.g. 0.30 = +30%) required to
      # hold a position overnight instead of squaring it off at EOD.
      def min_carry_roi
        (Mode.config.dig(:positional, :min_carry_roi) || 0.30).to_f
      end

      # Should this still-open tracker be carried overnight rather than closed at EOD?
      # Requires positional carry to be allowed for its index AND ROI above threshold.
      def carry_eligible?(tracker)
        index_key = tracker_index_key(tracker)
        return false unless index_key
        return false unless carry_allowed?(index_key: index_key)

        roi = tracker.last_pnl_pct.to_f
        roi >= min_carry_roi
      rescue StandardError => e
        Rails.logger.warn("[CarryPolicy] carry_eligible? #{e.class} - #{e.message}")
        false
      end

      # True for a tracker already tagged as a positional carry.
      def carried?(tracker)
        tracker.carry_mode.to_s == Mode::POSITIONAL
      end

      # True when a tagged carry should remain held (carry still allowed for its
      # index — e.g. not yet expiry day). Used by EOD/next-morning sweeps to skip it.
      def carry_still_valid?(tracker)
        return false unless carried?(tracker)

        index_key = tracker_index_key(tracker)
        return false unless index_key

        carry_allowed?(index_key: index_key)
      rescue StandardError => e
        Rails.logger.warn("[CarryPolicy] carry_still_valid? #{e.class} - #{e.message}")
        false
      end

      private

      def tracker_index_key(tracker)
        key = tracker.try(:index_key) || tracker.meta&.dig("index_key")
        key.to_s.upcase.presence
      end

      def resolve_expiry(index_key)
        analyzer = Options::DerivativeChainAnalyzer.new(index_key: index_key)
        analyzer.find_nearest_expiry
      end
    end
  end
end
