# frozen_string_literal: true

# DhanHQ::Auth (lib/DhanHQ/auth.rb, gem v3.3.0) builds its own bare Faraday
# connection with no JSON response middleware, unlike DhanHQ::Client which
# parses via ResponseHelper#parse_json. handle_response's
# `response.body.is_a?(Hash) ? response.body : {}` therefore discards every
# successful body (a JSON string) and returns {}, so Dhan::TokenManager's
# TOTP refresh (used by DhanhqErrorHandler/Placer auto-heal) always fails
# with "missing access_token or expires_at in response ({})".
module DhanHQ
  module Auth
    def self.handle_response(response, context:)
      body = response.body
      body = JSON.parse(body) if body.is_a?(String) && !body.strip.empty?
      body = {} unless body.is_a?(Hash)

      unless response.success?
        error_message = body["errorMessage"] || body["message"] || response.body.to_s
        raise DhanHQ::InvalidAuthenticationError,
              "#{context} failed: #{response.status} #{error_message}"
      end

      body
    end
    private_class_method :handle_response
  end
end
