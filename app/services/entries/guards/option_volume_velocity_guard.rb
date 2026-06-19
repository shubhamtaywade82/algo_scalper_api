# frozen_string_literal: true

module Entries
  module Guards
    # Entry guard that verifies that the option contract's volume velocity
    # (rate of change) is high enough to justify entry.
    class OptionVolumeVelocityGuard
      include BaseGuard

      def self.call(context)
        return PASS unless enabled?

        pick = context[:pick]
        security_id = pick[:security_id].to_s

        # Get stream window ticks for this option contract
        ticks = OptionsBuying::StateStore.stream_window(security_id)

        # If stream window is empty or too small, pass to avoid blocking during warmup
        return PASS if ticks.size < 3

        # Volume delta of recent ticks vs baseline
        volume_delta = OptionsBuying::TickMetrics.volume_delta(ticks.last(5))
        volume_baseline = OptionsBuying::StateStore.volume_threshold_baseline(security_id)

        return PASS unless volume_baseline&.positive?

        # Resolve volume velocity multiplier based on DTE
        dte = Trading::DteResolver.days_to_expiry(pick: pick, index_cfg: context[:index_cfg])
        multiplier = Trading::DteParameterResolver.volume_velocity_multiplier(dte: dte) || 2.0

        if volume_delta < (volume_baseline * multiplier)
          return { blocked: "Option contract volume velocity too low: delta #{volume_delta} < baseline #{volume_baseline.round(1)} * multiplier #{multiplier}" }
        end

        PASS
      rescue StandardError => e
        Rails.logger.warn("[OptionVolumeVelocityGuard] Error: #{e.class} - #{e.message}")
        PASS
      end

      def self.enabled?
        cfg = AlgoConfig.fetch.dig(:risk, :volume_velocity_gate) || {}
        cfg[:enabled] != false
      end
    end
  end
end
