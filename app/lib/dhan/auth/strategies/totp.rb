# frozen_string_literal: true

require "rotp"

module Dhan
  module Auth
    module Strategies
      # Fully-automated TOTP strategy (PRIMARY).
      # Generates a time-based OTP from DHAN_TOTP_SECRET and exchanges
      # client id + DHAN_PIN + OTP for a short-lived access token
      # directly with the Dhan auth endpoint.
      #
      # Required ENV:
      #   DHAN_CLIENT_ID or CLIENT_ID — Dhan client/user ID
      #   DHAN_PIN           - Dhan login PIN
      #   DHAN_TOTP_SECRET   - Base32 TOTP secret from Dhan 2FA setup
      class Totp < Base
        URL = "https://auth.dhan.co/app/generateAccessToken"

        def call
          client_id = client_id_from_env
          pin       = ENV.fetch("DHAN_PIN")
          totp_code = ROTP::TOTP.new(ENV.fetch("DHAN_TOTP_SECRET")).now

          # Dhan expects POST with query params and empty body (not JSON).
          response = Faraday.post(URL) do |req|
            req.params = {
              dhanClientId: client_id,
              pin: pin,
              totp: totp_code
            }
          end

          raise "TOTP auth failed (status=#{response.status}): #{response.body}" unless response.success?

          body = parse_json_body!(response.body)
          token, expiry_raw = extract_totp_credentials!(body)

          normalize_response(token: token, expiry: Time.parse(expiry_raw))
        end

        private

        def parse_json_body!(raw)
          JSON.parse(raw)
        rescue JSON::ParserError => e
          raise "TOTP response was not valid JSON (#{e.class}): #{raw.to_s[0, 200]}"
        end

        # Dhan may return HTTP 200 with {"status":"error","message":"..."} (no token keys).
        # Successful payloads use camelCase or snake_case keys.
        def extract_totp_credentials!(body)
          raise "TOTP response was not a JSON object" unless body.is_a?(Hash)

          if error_payload?(body)
            msg = body["message"].presence || body["errorMessage"].presence || "unknown error"
            raise "TOTP auth rejected: #{msg}"
          end

          token = body["accessToken"].presence || body["access_token"].presence
          expiry_raw = body["expiryTime"].presence || body["expires_at"].presence

          raise "TOTP response missing access token" if token.blank?
          raise "TOTP response missing expiry time" if expiry_raw.blank?

          [token, expiry_raw]
        end

        def error_payload?(body)
          body["status"].to_s.casecmp("error").zero?
        end

        def client_id_from_env
          ENV["DHAN_CLIENT_ID"].presence || ENV["CLIENT_ID"].presence ||
            raise(KeyError, "key not found: neither DHAN_CLIENT_ID nor CLIENT_ID is set")
        end
      end
    end
  end
end
