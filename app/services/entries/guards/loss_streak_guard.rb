# frozen_string_literal: true

module Entries
  module Guards
    class LossStreakGuard
      class << self
        include BaseGuard

        def call(context)
          return PASS unless config_enabled?

          index_key = context.dig(:index_cfg, :key).to_s
          return PASS if index_key.empty?
          return { blocked: "loss-streak cooldown active for #{index_key}" } if cooldown_active?(index_key)
          return PASS unless consecutive_losses_reached?(index_key)

          set_cooldown(index_key)
          { blocked: "loss-streak cooldown triggered for #{index_key}" }
        end

        private

        def config
          AlgoConfig.fetch[:loss_streak_guard] || {}
        rescue StandardError
          {}
        end

        def config_enabled?
          config[:enabled] == true
        end

        def loss_threshold
          value = config[:consecutive_losses_threshold].to_i
          value.positive? ? value : 2
        end

        def cooldown_minutes
          value = config[:cooldown_minutes].to_i
          value.positive? ? value : 30
        end

        def cooldown_key(index_key)
          "entries:loss_streak_guard:cooldown:#{index_key}"
        end

        def cooldown_active?(index_key)
          return true if Rails.cache.read(cooldown_key(index_key)).present?

          local_cooldown_active?(index_key)
        rescue StandardError
          local_cooldown_active?(index_key)
        end

        def set_cooldown(index_key)
          Rails.cache.write(cooldown_key(index_key), true, expires_in: cooldown_minutes.minutes)
          local_cooldowns[index_key] = Time.current + cooldown_minutes.minutes
        rescue StandardError
          local_cooldowns[index_key] = Time.current + cooldown_minutes.minutes
        end

        def consecutive_losses_reached?(index_key)
          positions = recent_positions(index_key)
          return false unless positions.size == loss_threshold

          positions.all? { |position| loss_exit?(position) }
        end

        def recent_positions(index_key)
          position_scope
            .where(status: :exited)
            .where("meta->>'index_key' = ?", index_key)
            .where(exited_at: Time.zone.today.all_day)
            .order(exited_at: :desc)
            .limit(loss_threshold)
        end

        def position_scope
          paper_trading_mode? ? PositionTracker.paper : PositionTracker.live
        end

        def loss_exit?(position)
          position.last_pnl_rupees.to_f.negative?
        end

        def local_cooldown_active?(index_key)
          expires_at = local_cooldowns[index_key]
          expires_at.present? && expires_at > Time.current
        end

        def local_cooldowns
          @local_cooldowns ||= {}
        end
      end
    end
  end
end
