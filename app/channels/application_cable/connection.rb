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

        false
      end

      provided_raw = request.params[:token].presence || bearer_token_from_header
      provided = provided_raw.to_s
      expected_str = expected.to_s
      return false if provided.blank?

      provided.bytesize == expected_str.bytesize &&
        ActiveSupport::SecurityUtils.secure_compare(provided, expected_str)
    end

    def bearer_token_from_header
      header = request.get_header('HTTP_AUTHORIZATION').to_s.strip
      return nil unless header.match?(/\ABearer\s+/i)

      header.sub(/\ABearer\s+/i, '').strip.presence
    end
  end
end
