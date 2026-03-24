# frozen_string_literal: true

module Dhan
  module Auth
    module Strategies
      # Manual / static-token strategy (development / fallback only).
      # Reads a pre-issued access token directly from ENV and assigns a
      # 24-hour expiry. Not suitable for long-running automation because
      # the token is never refreshed automatically.
      #
      # Required ENV:
      #   DHAN_ACCESS_TOKEN  - Pre-issued Dhan access token
      class Manual < Base
        def call
          token = ENV["DHAN_ACCESS_TOKEN"].presence
          raise "Manual token missing: set DHAN_ACCESS_TOKEN in ENV" if token.blank?

          normalize_response(
            token: token,
            expiry: 24.hours.from_now
          )
        end
      end
    end
  end
end
