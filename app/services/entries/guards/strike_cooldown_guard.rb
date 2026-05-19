# frozen_string_literal: true

module Entries
  module Guards
    # Blocks re-entry of the same option contract (security_id) within a
    # cooldown window after a STOP_LOSS / loss exit. Prevents chasing the
    # same strike after it just stopped you out.
    class StrikeCooldownGuard
      LOSS_EXIT_PATTERNS = %w[STOP_LOSS PREMIUM_MOMENTUM_FAILURE TRAILING_STOP].freeze

      class << self
        include BaseGuard

        def call(context)
          return PASS unless config_enabled?

          security_id = context.dig(:pick, :security_id).to_s
          return PASS if security_id.empty?

          last_loss_at = recent_loss_exit_at(security_id)
          return PASS if last_loss_at.nil?

          age_seconds = Time.current - last_loss_at
          window = cooldown_seconds
          return PASS if age_seconds >= window

          remaining = (window - age_seconds).round
          { blocked: "strike cooldown active for #{security_id} (#{remaining}s left)" }
        end

        private

        def config
          AlgoConfig.fetch[:strike_cooldown_guard] || {}
        rescue StandardError
          {}
        end

        def config_enabled?
          config[:enabled] != false
        end

        def cooldown_seconds
          value = config[:cooldown_minutes].to_i
          (value.positive? ? value : 20) * 60
        end

        def recent_loss_exit_at(security_id)
          position_scope
            .where(status: :exited, security_id: security_id)
            .where(exited_at: Time.zone.today.all_day)
            .where("last_pnl_rupees < 0")
            .order(exited_at: :desc)
            .limit(1)
            .pick(:exited_at)
        rescue StandardError
          nil
        end

        def position_scope
          paper_trading_mode? ? PositionTracker.paper : PositionTracker.live
        end

        def paper_trading_mode?
          AlgoConfig.fetch.dig(:paper_trading, :enabled) == true
        rescue StandardError
          false
        end
      end
    end
  end
end
