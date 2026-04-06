# frozen_string_literal: true

require 'securerandom'

module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :connection_id

    def connect
      reject_unauthorized_connection unless dashboard_token_valid?

      self.connection_id = SecureRandom.uuid
    end

    private

    def dashboard_token_valid?
      expected = ENV['API_DASHBOARD_TOKEN'].presence
      if expected.blank?
        # Fail closed whenever the app considers itself production (including stubs in specs).
        return false if Rails.env.production?
        return true if Rails.env.local?

        return false
      end

      provided_raw = cable_dashboard_token.presence || bearer_token_from_header
      provided = provided_raw.to_s
      expected_str = expected.to_s
      return false if provided.blank?

      provided.bytesize == expected_str.bytesize &&
        ActiveSupport::SecurityUtils.secure_compare(provided, expected_str)
    end

    def cable_dashboard_token
      # Prefer explicit query access: some Cable/proxy stacks expose QUERY_STRING more reliably
      # than the merged params hash during the WebSocket handshake.
      qp = request.query_parameters
      qp['token'].presence || qp[:token].presence || request.params[:token].presence
    rescue StandardError
      request.params[:token].presence
    end

    def bearer_token_from_header
      header = request.get_header('HTTP_AUTHORIZATION').to_s.strip
      return nil unless header.match?(/\ABearer\s+/i)

      header.sub(/\ABearer\s+/i, '').strip.presence
    end
  end
end
