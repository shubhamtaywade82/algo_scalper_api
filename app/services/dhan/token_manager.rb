# frozen_string_literal: true

module Dhan
  # Orchestrates Dhan access-token lifecycle for the trading daemon.
  #
  # Auth strategy is selected at runtime via DHAN_AUTH_MODE:
  #   totp       - fully automated TOTP login (default)
  #   manual     - static DHAN_ACCESS_TOKEN from ENV
  #   renew      - extend an existing token via Dhan RenewToken API
  #   authority  - delegate to external authority server (optional)
  #
  # All paths return a token string or nil; never raise outside #refresh!.
  class TokenManager
    BUFFER_MINUTES = 30

    class << self
      # Returns the current valid token, refreshing if needed.
      # Returns nil on failure (callers must handle).
      def current_token
        current_token!
      end

      def current_token!
        token_data = cached_token

        if token_data.nil? || expiring?(token_data)
          refreshed = refresh!
          return refreshed if refreshed.present?

          # Refresh failed — return the stale token only if not yet expired
          return nil if token_data.nil? ||
                        token_data[:expiry_time].nil? ||
                        token_data[:expiry_time] <= Time.current
        end

        token_data&.dig(:token)
      end

      # Fetches a fresh token via the configured auth strategy and persists it.
      # Thread-safe via Mutex. Returns the token string or nil on failure.
      def refresh!(force: false)
        mutex.synchronize do
          token_data = cached_token
          return token_data[:token] if token_data && !expiring?(token_data) && !force

          strategy  = Dhan::Auth::StrategyResolver.resolve
          response  = strategy.call

          access_token = response[:access_token]
          expiry_time  = response[:expiry_time]

          persist_token(access_token, expiry_time)
          cache_token(access_token, expiry_time)
          apply_token_to_runtime!(access_token)
          restart_websocket!

          access_token
        end
      rescue StandardError => e
        Rails.logger.error("[DHAN] Token refresh failed (mode=#{ENV.fetch('DHAN_AUTH_MODE', 'totp')}): #{e.class} - #{e.message}")
        nil
      end

      def clear_cache!
        mutex.synchronize do
          @cached_token = nil
          DhanAccessToken.delete_all
        end
        true
      end

      private

      def cached_token
        @cached_token ||= load_from_db
      end

      def cache_token(token, expiry_time)
        @cached_token = { token: token, expiry_time: expiry_time }
      end

      def expiring?(token_data)
        token_data[:expiry_time] <= BUFFER_MINUTES.minutes.from_now
      end

      def load_from_db
        record = DhanAccessToken.first
        return nil unless record

        { token: record.token, expiry_time: record.expiry_time }
      end

      def persist_token(token, expiry_time)
        DhanAccessToken.transaction do
          DhanAccessToken.delete_all
          DhanAccessToken.create!(token: token, expiry_time: expiry_time)
        end
      end

      def apply_token_to_runtime!(access_token)
        ENV["ACCESS_TOKEN"]      = access_token
        ENV["DHAN_ACCESS_TOKEN"] = access_token

        DhanHQ.configure do |config|
          config.access_token = access_token
        end
      rescue StandardError => e
        Rails.logger.error("[DHAN] Failed to apply token to runtime: #{e.class} - #{e.message}")
      end

      def restart_websocket!
        return unless defined?(Live::MarketFeedHub)

        hub = Live::MarketFeedHub.instance
        return unless hub.running?

        Rails.logger.info("[DHAN] Restarting MarketFeedHub after token refresh")
        hub.stop!
        hub.start!
      rescue StandardError => e
        Rails.logger.error("[DHAN] Failed to restart MarketFeedHub: #{e.class} - #{e.message}")
      end

      def mutex
        @mutex ||= Mutex.new
      end
    end
  end
end
