# frozen_string_literal: true

module Dhan
  class TokenManager
    BUFFER_MINUTES = 30
    REQUIRED_ENV_KEYS = %w[DHAN_PIN DHAN_TOTP_SECRET].freeze

    class << self
      def current_token
        current_token!
      end

      def current_token!
        token_data = cached_token

        if token_data.nil? || expiring?(token_data)
          refreshed_token = refresh!
          return refreshed_token if refreshed_token.present?
          token_data = cached_token
        end

        token_data&.dig(:token)
      end

      def refresh!
        mutex.synchronize do
          token_data = cached_token
          return token_data[:token] if token_data && !expiring?(token_data)
          return nil unless credentials_available?

          Rails.logger.info('[DHAN] Regenerating token via TOTP...')

          response = DhanHQ::Auth.generate_access_token(
            dhan_client_id: creds[:client_id],
            pin: creds[:pin],
            totp: generate_totp
          )

          access_token = response['accessToken']
          expiry_time = Time.parse(response['expiryTime'])

          persist_token(access_token, expiry_time)
          cache_token(access_token, expiry_time)
          apply_token_to_runtime!(access_token)
          restart_websocket!

          access_token
        end
      rescue StandardError => e
        Rails.logger.error("[DHAN] Token refresh failed: #{e.class} - #{e.message}")
        nil
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
        DhanHQ::Auth.generate_totp(creds[:totp_secret])
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
        Dhan::Ws::FeedListener.restart! if defined?(Dhan::Ws::FeedListener)
      end

      def mutex
        @mutex ||= Mutex.new
      end
    end
  end
end
