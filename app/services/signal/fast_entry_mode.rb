# frozen_string_literal: true

module Signal
  # Toggle for lifecycle / paper testing: enter on 1m Supertrend direction without
  # intraday options-buying entry gates (breakout arm, RSI bias, weak-momentum skip).
  # Exits, risk manager, sizing, and core EntryGuard checks remain active.
  class FastEntryMode
    CACHE_TTL = 30.seconds

    class << self
      def enabled?
        refresh_cache_if_stale
        @enabled
      end

      def effective_momentum_score(raw_score)
        return raw_score unless enabled?

        3
      end

      def status
        {
          persisted: persisted_enabled?,
          effective: enabled?,
          env_override: env_override?
        }
      end

      def persisted_enabled?
        AlgoConfig.fetch.dig(:signals, :fast_entry_mode, :enabled) == true
      rescue StandardError
        false
      end

      def env_override?
        env = ENV.fetch('FAST_ENTRY_MODE', nil)
        return false if env.nil?

        !env.to_s.strip.empty?
      end

      def reset!
        @enabled = nil
        @cached_at = nil
        @logged = nil
      end

      private

      def refresh_cache_if_stale
        now = Time.current
        return if @cached_at && (now - @cached_at) < CACHE_TTL

        @cached_at = now
        @enabled = resolve_enabled
        log_mode_once if @enabled
      end

      def resolve_enabled
        env = ENV.fetch('FAST_ENTRY_MODE', nil)
        unless env.nil?
          stripped = env.to_s.strip
          return false if stripped.empty?

          return ActiveModel::Type::Boolean.new.cast(stripped)
        end

        AlgoConfig.fetch.dig(:signals, :fast_entry_mode, :enabled) == true
      rescue StandardError
        false
      end

      def log_mode_once
        return if @logged

        @logged = true
        Rails.logger.warn(
          '[FastEntryMode] ENABLED — 1m Supertrend entries; intraday breakout/OI/momentum entry gates bypassed. ' \
          'Set FAST_ENTRY_MODE=false or signals.fast_entry_mode.enabled: false for production intraday path.'
        )
      end
    end
  end
end
