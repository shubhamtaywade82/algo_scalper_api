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
      return true if expected.blank?

      provided = request.params[:token].presence || bearer_token_from_header
      provided.present? &&
        expected.bytesize == provided.bytesize &&
        ActiveSupport::SecurityUtils.secure_compare(provided, expected)
    end

    def bearer_token_from_header
      header = request.get_header('HTTP_AUTHORIZATION').to_s.strip
      return nil unless header.match?(/\ABearer\s+/i)

      header.sub(/\ABearer\s+/i, '').strip.presence
    end
  end
end
