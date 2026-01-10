# frozen_string_literal: true

module Options
  module StrikeQualification
    # ExpectedMoveValidator answers:
    # "If price moves as expected, will THIS option move enough to justify entry?"
    #
    # Deterministic, static delta buckets (no live Greeks).
    class ExpectedMoveValidator < ApplicationService
      VALID_PERMISSIONS = %i[execution_only scale_ready full_deploy].freeze
      VALID_STRIKE_TYPES = %i[ATM ATM_PLUS_1 ATM_MINUS_1].freeze

      def call(index_key:, strike_type:, permission:, expected_spot_move:, option_ltp:)
        index = index_key.to_s.strip.upcase
        perm = permission.to_s.strip.downcase.to_sym
        st = normalize_strike_type(strike_type)

        return blocked('invalid_permission') unless VALID_PERMISSIONS.include?(perm)
        return blocked('invalid_strike_type') unless VALID_STRIKE_TYPES.include?(st)
        return blocked('invalid_expected_spot_move') unless expected_spot_move.to_f.positive?
        return blocked('invalid_option_ltp') unless option_ltp.to_f.positive?

        return blocked('sensex_execution_only_blocked') if index == 'SENSEX' && perm == :execution_only

        delta = delta_bucket(index: index, strike_type: st)
        threshold = threshold_points(index: index, permission: perm)
        return blocked('unsupported_index') unless delta && threshold

        expected_premium = expected_spot_move.to_f * delta

        if expected_premium < threshold
          return blocked(
            'expected_premium_below_threshold',
            expected_premium: expected_premium,
            threshold: threshold,
            delta: delta
          )
        end

        ok(expected_premium: expected_premium, threshold: threshold, delta: delta)
      rescue StandardError => e
        Rails.logger.error("[Options::StrikeQualification::ExpectedMoveValidator] #{e.class} - #{e.message}")
        blocked('error')
      end

      private

      def normalize_strike_type(value)
        sym = value.to_s.strip.upcase.to_sym
        return :ATM if sym == :ATM
        return :ATM_PLUS_1 if sym == :ATM_PLUS_1
        return :ATM_MINUS_1 if sym == :ATM_MINUS_1

        sym
      end

      def delta_bucket(index:, strike_type:)
        case index
        when 'NIFTY'
          strike_type == :ATM ? 0.48 : 0.40
        when 'SENSEX'
          strike_type == :ATM ? 0.50 : 0.42
        else
          nil
        end
      end

      def threshold_points(index:, permission:)
        case index
        when 'NIFTY'
          {
            execution_only: 4.0,
            scale_ready: 8.0,
            full_deploy: 12.0
          }[permission]
        when 'SENSEX'
          {
            execution_only: nil, # Always blocked earlier
            scale_ready: 15.0,
            full_deploy: 25.0
          }[permission]
        else
          nil
        end
      end

      def ok(payload)
        { ok: true }.merge(payload)
      end

      def blocked(reason, details = {})
        { ok: false, reason: reason }.merge(details)
      end
    end
  end
end

