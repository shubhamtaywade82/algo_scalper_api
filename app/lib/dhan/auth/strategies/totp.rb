# frozen_string_literal: true

require "rotp"

module Dhan
  module Auth
    module Strategies
      # Fully-automated TOTP strategy (PRIMARY).
      # Generates a time-based OTP from DHAN_TOTP_SECRET and exchanges
      # DHAN_CLIENT_ID + DHAN_PIN + OTP for a short-lived access token
      # directly with the Dhan auth endpoint.
      #
      # Required ENV:
      #   DHAN_CLIENT_ID     - Dhan client/user ID
      #   DHAN_PIN           - Dhan login PIN
      #   DHAN_TOTP_SECRET   - Base32 TOTP secret from Dhan 2FA setup
      class Totp < Base
        URL = "https://auth.dhan.co/app/generateAccessToken"

        def call
          client_id = ENV.fetch("DHAN_CLIENT_ID")
          pin       = ENV.fetch("DHAN_PIN")
          totp_code = ROTP::TOTP.new(ENV.fetch("DHAN_TOTP_SECRET")).now

          response = Faraday.post(URL) do |req|
            req.headers["Content-Type"] = "application/json"
            req.body = JSON.generate(
              dhanClientId: client_id,
              pin: pin,
              totp: totp_code
            )
          end

          raise "TOTP auth failed (status=#{response.status}): #{response.body}" unless response.success?

          body = JSON.parse(response.body)
          token  = body["accessToken"].presence
          expiry = body["expiryTime"].presence

          raise "TOTP response missing accessToken" if token.blank?
          raise "TOTP response missing expiryTime" if expiry.blank?

          normalize_response(token: token, expiry: Time.parse(expiry))
        end
      end
    end
  end
end
