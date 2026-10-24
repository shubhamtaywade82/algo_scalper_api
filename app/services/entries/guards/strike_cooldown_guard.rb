# frozen_string_literal: true

module Entries
  module Guards
    # Blocks re-entry of the same option contract (security_id) within a
    # cooldown window after a recent exit. Prevents chop re-entry on the
    # same strike after give-back or stop-out.
    class StrikeCooldownGuard
      class << self
        include BaseGuard

        def call(context)
          return PASS unless config_enabled?

          security_id = context.dig(:pick, :security_id).to_s
          return PASS if security_id.empty?

          last_exit = recent_exit(security_id)
          return PASS if last_exit.nil?

          last_exit_at, last_pnl = last_exit
          age_seconds = Time.current - last_exit_at
          window = cooldown_seconds_for(last_pnl)
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

        def after_any_exit?
          config[:after_any_exit] != false
        end

        def cooldown_seconds_for(last_pnl_rupees)
          loss_minutes = config[:loss_cooldown_minutes].to_i
          base_minutes = config[:cooldown_minutes].to_i
          base_minutes = 20 if base_minutes <= 0

          minutes = if after_any_exit? && last_pnl_rupees.to_f.negative? && loss_minutes.positive?
                      loss_minutes
                    else
                      base_minutes
                    end

          minutes * 60
        end

        def recent_exit(security_id)
          scope = position_scope
                  .where(status: :exited, security_id: security_id)
                  .where(exited_at: Time.zone.today.all_day)
                  .order(exited_at: :desc)
                  .limit(1)

          scope = scope.where('last_pnl_rupees < 0') unless after_any_exit?

          scope.pick(:exited_at, :last_pnl_rupees)
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
