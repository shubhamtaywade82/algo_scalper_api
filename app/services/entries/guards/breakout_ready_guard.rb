# frozen_string_literal: true

module Entries
  module Guards
    class BreakoutReadyGuard
      include BaseGuard

      def self.call(context)
        return PASS if Signal::FastEntryMode.enabled?
        return PASS unless OptionsBuying::Mode.breakout_enabled?
        return PASS if positional_carry_active?(context)
        return PASS if expiry_day_locked?(context)

        index_key = context.dig(:index_cfg, :key)
        return PASS unless index_key

        direction = entry_direction(context)
        # Bullish/long-CE needs the CE call-wall resistance; bearish/long-PE needs the
        # PE put-wall support. Each direction arms independently.
        level = direction == :bullish ? OptionsBuying::StateStore.resistance(index_key) : OptionsBuying::StateStore.support(index_key)
        level_name = direction == :bullish ? 'resistance' : 'support'
        unless level&.positive?
          # No radar level yet — ChainRadar hasn't run or failed. Fail open so entries
          # aren't blocked during warmup, but log so a dead radar is visible.
          Rails.logger.warn("[BreakoutReadyGuard] no radar #{level_name} for #{index_key} (#{direction}) — breakout gate skipped")
          return PASS
        end

        return PASS if OptionsBuying::StateStore.breakout_ready?(index_key, direction: direction)

        { blocked: "#{direction} breakout not armed for #{index_key}" }
      rescue StandardError => e
        # Core entry gate — fail CLOSED: an error here must not let an unarmed entry through.
        Rails.logger.error("[BreakoutReadyGuard] #{e.class} - #{e.message}")
        { blocked: 'breakout guard unavailable' }
      end

      def self.entry_direction(context)
        context[:direction].to_s.downcase == 'bearish' ? :bearish : :bullish
      end

      def self.positional_carry_active?(context)
        return false unless OptionsBuying::Mode.positional_active?

        index_key = context.dig(:index_cfg, :key)
        return false unless index_key

        OptionsBuying::CarryPolicy.carry_allowed?(index_key: index_key)
      end

      def self.expiry_day_locked?(context)
        index_key = context.dig(:index_cfg, :key)
        return false unless index_key

        lockout_after = OptionsBuying::Mode.config.dig(:expiry_day, :lockout_after)
        return false if lockout_after.blank?

        return false unless OptionsBuying::CarryPolicy.expiry_day?(index_key: index_key)

        Time.zone.now.strftime('%H:%M') >= lockout_after.to_s
      rescue StandardError
        false
      end
    end
  end
end
