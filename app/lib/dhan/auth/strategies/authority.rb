# frozen_string_literal: true

module Dhan
  module Auth
    module Strategies
      # Authority-server strategy (backward-compatible default).
      # Delegates token acquisition to an external authority server that
      # manages TOTP / OAuth on behalf of this app. Useful when a separate
      # service (e.g. algo_trading_api) owns the Dhan credentials.
      #
      # Required ENV:
      #   TRADER_API_BASE_URL        - Base URL of the authority server
      #                                (e.g. https://authority.example.com)
      #   DHAN_TOKEN_ACCESS_TOKEN    - Bearer token used to authenticate
      #                                this app to the authority server
      class Authority < Base
        def call
          token_url = build_token_url
          bearer    = ENV["DHAN_TOKEN_ACCESS_TOKEN"].presence

          raise "Authority URL invalid/missing: set TRADER_API_BASE_URL" if token_url.blank?
          raise "Authority bearer missing: set DHAN_TOKEN_ACCESS_TOKEN"   if bearer.blank?

          response = Faraday.get(token_url) do |req|
            req.headers["Authorization"] = "Bearer #{bearer}"
          end

          raise "Authority request failed (status=#{response.status})" unless response.success?

          data   = JSON.parse(response.body)
          token  = data["access_token"].presence || data["accessToken"].presence
          expiry = data["expires_at"].presence   || data["expiryTime"].presence

          raise "Authority response missing access_token" if token.blank?
          raise "Authority response missing expires_at"   if expiry.blank?

          normalize_response(token: token, expiry: Time.parse(expiry))
        end

        private

        def build_token_url
          raw_base = ENV["TRADER_API_BASE_URL"].to_s.strip
          return nil if raw_base.blank? || raw_base.include?("<") || raw_base.include?(">")

          uri = URI.parse(raw_base)
          return nil unless uri.is_a?(URI::HTTP) && uri.host.present?

          "#{raw_base.chomp('/')}/auth/dhan/token"
        rescue URI::InvalidURIError
          nil
        end
      end
    end
  end
end
