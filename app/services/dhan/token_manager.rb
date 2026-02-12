# frozen_string_literal: true

module Dhan
  class TokenManager
    BUFFER_MINUTES = 30

    class << self
      def current_token!
        return nil unless token_table_ready?

        token_record = DhanAccessToken.first

        if token_record.nil? || token_record.expired? || token_record.expiring_soon?(buffer_minutes: BUFFER_MINUTES)
          refresh!
          token_record = DhanAccessToken.first
        end

        token_record&.token
      end

      def refresh!
        return nil unless token_table_ready?

        mutex.synchronize do
          token_record = DhanAccessToken.first

          if token_record && !token_record.expired? && !token_record.expiring_soon?(buffer_minutes: BUFFER_MINUTES)
            apply_token_to_runtime!(token_record.token)
            return token_record.token
          end

          response = DhanHQ::Auth.generate_access_token(
            dhan_client_id: env_client_id,
            pin: env_pin,
            totp: DhanHQ::Auth.generate_totp(env_totp_secret)
          )

          access_token = response.fetch('accessToken')
          expiry_time = Time.parse(response.fetch('expiryTime'))

          DhanAccessToken.transaction do
            DhanAccessToken.delete_all
            DhanAccessToken.create!(token: access_token, expiry_time: expiry_time)
          end

          apply_token_to_runtime!(access_token)
          restart_websockets!

          access_token
        end
      rescue StandardError => e
        Rails.logger.error("[Dhan::TokenManager] #{e.class} - #{e.message}")
        nil
      end

      private

      def mutex
        @mutex ||= Mutex.new
      end

      def env_client_id
        ENV['DHAN_CLIENT_ID'].presence || ENV.fetch('CLIENT_ID')
      end

      def env_pin
        ENV.fetch('DHAN_PIN')
      end

      def env_totp_secret
        ENV.fetch('DHAN_TOTP_SECRET')
      end

      def token_table_ready?
        return false unless defined?(ActiveRecord::Base)

        ActiveRecord::Base.connection.schema_cache.data_source_exists?('dhan_access_tokens')
      rescue StandardError
        false
      end

      def apply_token_to_runtime!(access_token)
        # Keep both naming conventions in sync
        ENV['ACCESS_TOKEN'] = access_token
        ENV['DHAN_ACCESS_TOKEN'] = access_token

        # Ensure gem clients pick up the new token even if they don't re-read ENV
        DhanHQ.configure do |config|
          config.access_token = access_token
        end
      rescue StandardError => e
        Rails.logger.error("[Dhan::TokenManager] apply_token_to_runtime! #{e.class} - #{e.message}")
        nil
      end

      def restart_websockets!
        return if Rails.env.test?
        return if ENV['DISABLE_TRADING_SERVICES'] == '1'

        # Restart WebSockets after refresh (old token becomes invalid immediately).
        DhanHQ::WS.disconnect_all_local! if defined?(DhanHQ::WS)

        Live::MarketFeedHub.instance.stop! if defined?(Live::MarketFeedHub)
        Live::OrderUpdateHub.instance.stop! if defined?(Live::OrderUpdateHub)

        Live::MarketFeedHub.instance.start! if defined?(Live::MarketFeedHub)
        Live::OrderUpdateHub.instance.start! if defined?(Live::OrderUpdateHub)
      rescue StandardError => e
        Rails.logger.error("[Dhan::TokenManager] restart_websockets! #{e.class} - #{e.message}")
        nil
      end
    end
  end
end

