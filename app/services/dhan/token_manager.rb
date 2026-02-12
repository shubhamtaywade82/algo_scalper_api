# # frozen_string_literal: true

# module Dhan
#   class TokenManager
#     BUFFER_MINUTES = 30

#     class << self
#       def current_token!
#         return nil unless token_table_ready?

#         token_record = DhanAccessToken.first

#         if token_record.nil? || token_record.expired? || token_record.expiring_soon?(buffer_minutes: BUFFER_MINUTES)
#           refresh!
#           token_record = DhanAccessToken.first
#         end

#         token_record&.token
#       end

#       def refresh!
#         return nil unless token_table_ready?

#         mutex.synchronize do
#           token_record = DhanAccessToken.first

#           if token_record && !token_record.expired? && !token_record.expiring_soon?(buffer_minutes: BUFFER_MINUTES)
#             apply_token_to_runtime!(token_record.token)
#             return token_record.token
#           end

#           response = DhanHQ::Auth.generate_access_token(
#             dhan_client_id: env_client_id,
#             pin: env_pin,
#             totp: DhanHQ::Auth.generate_totp(env_totp_secret)
#           )

#           access_token = response.fetch('accessToken')
#           expiry_time = Time.parse(response.fetch('expiryTime'))

#           DhanAccessToken.transaction do
#             DhanAccessToken.delete_all
#             DhanAccessToken.create!(token: access_token, expiry_time: expiry_time)
#           end

#           apply_token_to_runtime!(access_token)
#           restart_websockets!

#           access_token
#         end
#       rescue StandardError => e
#         Rails.logger.error("[Dhan::TokenManager] #{e.class} - #{e.message}")
#         nil
#       end

#       private

#       def mutex
#         @mutex ||= Mutex.new
#       end

#       def env_client_id
#         ENV['DHAN_CLIENT_ID'].presence || ENV.fetch('CLIENT_ID')
#       end

#       def env_pin
#         ENV.fetch('DHAN_PIN')
#       end

#       def env_totp_secret
#         ENV.fetch('DHAN_TOTP_SECRET')
#       end

#       def token_table_ready?
#         return false unless defined?(ActiveRecord::Base)

#         ActiveRecord::Base.connection.schema_cache.data_source_exists?('dhan_access_tokens')
#       rescue StandardError
#         false
#       end

#       def apply_token_to_runtime!(access_token)
#         # Keep both naming conventions in sync
#         ENV['ACCESS_TOKEN'] = access_token
#         ENV['DHAN_ACCESS_TOKEN'] = access_token

#         # Ensure gem clients pick up the new token even if they don't re-read ENV
#         DhanHQ.configure do |config|
#           config.access_token = access_token
#         end
#       rescue StandardError => e
#         Rails.logger.error("[Dhan::TokenManager] apply_token_to_runtime! #{e.class} - #{e.message}")
#         nil
#       end

#       def restart_websockets!
#         return if Rails.env.test?
#         return if ENV['DISABLE_TRADING_SERVICES'] == '1'

#         # Restart WebSockets after refresh (old token becomes invalid immediately).
#         DhanHQ::WS.disconnect_all_local! if defined?(DhanHQ::WS)

#         Live::MarketFeedHub.instance.stop! if defined?(Live::MarketFeedHub)
#         Live::OrderUpdateHub.instance.stop! if defined?(Live::OrderUpdateHub)

#         Live::MarketFeedHub.instance.start! if defined?(Live::MarketFeedHub)
#         Live::OrderUpdateHub.instance.start! if defined?(Live::OrderUpdateHub)
#       rescue StandardError => e
#         Rails.logger.error("[Dhan::TokenManager] restart_websockets! #{e.class} - #{e.message}")
#         nil
#       end
#     end
#   end
# end


module Dhan
  class TokenManager
    BUFFER_MINUTES = 30

    class << self
      def current_token!
        token_data = cached_token

        if token_data.nil? || expiring?(token_data)
          refresh!
          token_data = cached_token
        end

        token_data[:token]
      end

      def refresh!
        mutex.synchronize do
          token_data = cached_token

          return token_data[:token] if token_data && !expiring?(token_data)

          Rails.logger.info "[DHAN] Regenerating token via TOTP..."

          response = DhanHQ::Auth.generate_access_token(
            dhan_client_id: creds[:client_id],
            pin: creds[:pin],
            totp: generate_totp
          )

          access_token = response["accessToken"]
          expiry_time  = Time.parse(response["expiryTime"])

          persist_token(access_token, expiry_time)
          cache_token(access_token, expiry_time)

          restart_websocket!

          access_token
        end
      end

      private

      # ===============================
      # In-Memory Cache
      # ===============================

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

      # ===============================
      # DB Persistence
      # ===============================

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

      # ===============================
      # Utilities
      # ===============================

      def generate_totp
        DhanHQ::Auth.generate_totp(creds[:totp_secret])
      end

      def creds
        Rails.application.credentials.dhan
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