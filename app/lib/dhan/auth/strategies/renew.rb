# frozen_string_literal: true

module Dhan
  module Auth
    module Strategies
      # Token-renewal strategy (secondary automation).
      # Exchanges the currently-persisted Dhan token for a fresh one via
      # the Dhan RenewToken API. Requires an existing, non-expired token in
      # the database. Use alongside Manual or TOTP for the initial token.
      #
      # Required ENV:
      #   DHAN_CLIENT_ID  - Dhan client/user ID
      # Required DB:
      #   DhanAccessToken.first  - a live access token to renew from
      class Renew < Base
        URL = "https://api.dhan.co/v2/RenewToken"

        def call
          existing = DhanAccessToken.first
          raise "No existing token to renew: run TOTP or Manual strategy first" unless existing

          response = Faraday.post(URL) do |req|
            req.headers["Content-Type"] = "application/json"
            req.headers["access-token"]  = existing.token
            req.headers["dhanClientId"]  = ENV.fetch("DHAN_CLIENT_ID")
          end

          raise "Renew failed (status=#{response.status}): #{response.body}" unless response.success?

          body   = JSON.parse(response.body)
          token  = body["accessToken"].presence
          expiry = body["expiryTime"].presence

          raise "Renew response missing accessToken" if token.blank?
          raise "Renew response missing expiryTime" if expiry.blank?

          normalize_response(token: token, expiry: Time.parse(expiry))
        end
      end
    end
  end
end
