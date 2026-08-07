# frozen_string_literal: true

module Dhan
  class TokenManager
    BUFFER_MINUTES = 30
    REQUIRED_ENV_KEYS = %w[DHAN_PIN DHAN_TOTP_SECRET].freeze
    TOTP_COOLDOWN_HOURS = 12

    class << self
      def current_token
        current_token!
      end

      def current_token!
        token_data = cached_token

        if token_data.nil? || expiring?(token_data)
          refreshed_token = refresh!
          return refreshed_token if refreshed_token.present?

          # If refresh failed and we have no token at all, or the one we have is expired, return nil
          return nil if token_data.nil? || token_data[:expiry_time] <= Time.current
        end

        token_data&.dig(:token)
      end

      def refresh!(force: false)
        mutex.synchronize do
          token_data = cached_token
          return token_data[:token] if token_data && !expiring?(token_data) && !force
          return nil unless credentials_available?

          env_token = static_env_token
          if totp_cooldown_active?
            Rails.logger.debug("[DHAN] TOTP cooldown until #{@totp_refresh_cooldown_until&.strftime('%H:%M %Z')}; using ENV token")
            cache_token(env_token, @totp_refresh_cooldown_until) if env_token.present?
            return env_token
          end

          Rails.logger.info("[DHAN] Regenerating token via TOTP... (force=#{force})")

          response = DhanHQ::Auth.generate_access_token(
            dhan_client_id: creds[:client_id],
            pin: creds[:pin],
            totp: generate_totp
          )

          unless response.is_a?(Hash)
            Rails.logger.error("[DHAN] Token refresh failed: response is not a Hash (#{response.inspect})")
            return nil
          end

          if response['status'] == 'error'
            msg = response['message'] || ''
            if too_many_attempts?(msg) && env_token.present?
              @totp_refresh_cooldown_until = TOTP_COOLDOWN_HOURS.hours.from_now
              cache_token(env_token, @totp_refresh_cooldown_until)
              Rails.logger.warn(
                "[DHAN] TOTP rate-limited (Too many attempts); using ENV token for next #{TOTP_COOLDOWN_HOURS} hours"
              )
              return env_token
            end
            Rails.logger.error("[DHAN] Token refresh failed: #{msg.presence || response.inspect}")
            return nil
          end

          access_token = response['access_token'] || response['accessToken']
          expiry_time_raw = response['expires_at'] || response['expiryTime']

          if access_token.blank? || expiry_time_raw.blank?
            Rails.logger.error("[DHAN] Token refresh failed: missing access_token or expires_at in response (#{response.inspect})")
            return nil
          end

          expiry_time = Time.parse(expiry_time_raw)

          persist_token(access_token, expiry_time)
          cache_token(access_token, expiry_time)
          apply_token_to_runtime!(access_token)
          broadcast_token_to_redis(access_token, expiry_time)
          restart_websocket!

          access_token
        end
      rescue StandardError => e
        Rails.logger.error("[DHAN] Token refresh failed: #{e.class} - #{e.message}")
        nil
      end

      def clear_cache!
        mutex.synchronize do
          @cached_token = nil
          @totp_refresh_cooldown_until = nil
          DhanAccessToken.delete_all
        end
        true
      end

      private

      def cached_token
        @cached_token ||= load_from_db
      end

      def cache_token(token, expiry_time)
        @cached_token = {
          token: token,
          expiry_time: expiry_time
        }
      end

      def expiring?(token_data)
        token_data[:expiry_time] <= BUFFER_MINUTES.minutes.from_now
      end

      def load_from_db
        record = DhanAccessToken.first
        return nil unless record

        {
          token: record.token,
          expiry_time: record.expiry_time
        }
      end

      def persist_token(token, expiry_time)
        DhanAccessToken.transaction do
          DhanAccessToken.delete_all
          DhanAccessToken.create!(
            token: token,
            expiry_time: expiry_time
          )
        end
      end

      def generate_totp
        secret = creds[:totp_secret]
        if secret.blank?
          Rails.logger.error("[DHAN] TOTP Secret is blank")
          return nil
        end
        unless secret.is_a?(String)
          Rails.logger.error("[DHAN] TOTP Secret is not a String: #{secret.class}")
          return nil
        end
        DhanHQ::Auth.generate_totp(secret)
      end

      def creds
        @creds ||= begin
          env = {
            client_id: ENV['DHAN_CLIENT_ID'].presence || ENV['CLIENT_ID'].presence,
            pin: ENV['DHAN_PIN'].presence,
            totp_secret: ENV['DHAN_TOTP_SECRET'].presence
          }

          if env.values.all?(&:present?)
            env
          else
            cred = Rails.application.credentials.dhan
            {
              client_id: cred&.dig(:client_id),
              pin: cred&.dig(:pin),
              totp_secret: cred&.dig(:totp_secret)
            }
          end
        end
      end

      def credentials_available?
        missing = []
        missing << 'client_id' if creds[:client_id].blank?
        missing << 'pin' if creds[:pin].blank?
        missing << 'totp_secret' if creds[:totp_secret].blank?

        return true if missing.empty?

        Rails.logger.warn(
          "[DHAN] Token refresh skipped: missing credentials #{missing.join(', ')}. " \
          "Set DHAN_CLIENT_ID/CLIENT_ID, #{REQUIRED_ENV_KEYS.join(', ')} or Rails credentials.dhan."
        )
        false
      end

      def apply_token_to_runtime!(access_token)
        ENV['ACCESS_TOKEN'] = access_token
        ENV['DHAN_ACCESS_TOKEN'] = access_token

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

      def static_env_token
        ENV['DHAN_ACCESS_TOKEN'].presence || ENV['ACCESS_TOKEN'].presence
      end

      def too_many_attempts?(message)
        message.to_s.include?('Too many attempts')
      end

      def totp_cooldown_active?
        return false unless @totp_refresh_cooldown_until

        Time.current < @totp_refresh_cooldown_until
      end

      def broadcast_token_to_redis(access_token, expiry_time)
        redis = Redis.new(url: ENV.fetch('REDIS_URL', 'redis://127.0.0.1:6379/0'))
        client_id = creds[:client_id]

        redis.set('dhan:auth:access_token', access_token)
        redis.set('dhan:auth:client_id', client_id) if client_id.present?
        redis.set('dhan:auth:expiry', expiry_time.to_i)

        payload = { token: access_token, client_id: client_id, expires_at: expiry_time.iso8601 }.to_json
        redis.publish('dhan:auth:rotated', payload)
      rescue StandardError => e
        Rails.logger.error("[DHAN] Redis token broadcast failed: #{e.class} - #{e.message}")
      end
    end
  end
end

