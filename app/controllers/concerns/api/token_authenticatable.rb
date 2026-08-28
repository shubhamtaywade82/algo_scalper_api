# frozen_string_literal: true

module Api
  # Optional Bearer / X-Api-Key checks for dashboard vs operator API tiers.
  #
  # When +API_DASHBOARD_TOKEN+ or +API_OPERATOR_TOKEN+ is unset, the corresponding
  # check is skipped (backward compatible). Set env vars in production to enforce.
  module TokenAuthenticatable
    extend ActiveSupport::Concern

    private

    def authenticate_dashboard_token!
      require_api_token!(ENV.fetch('API_DASHBOARD_TOKEN', nil), tier: :dashboard)
    end

    def authenticate_operator_token!
      require_api_token!(ENV.fetch('API_OPERATOR_TOKEN', nil), tier: :operator)
    end

    def require_api_token!(expected, tier:)
      expected = expected.presence
      if expected.blank?
        if Rails.env.production?
          Rails.logger.warn("[#{self.class.name}] No #{tier} token configured - denying request in production")
          render json: { error: 'server_configuration_error' }, status: :forbidden
          return nil
        end
        return
      end
      return if token_matches?(provided_api_token, expected)

      Rails.logger.warn("[#{self.class.name}] #{tier} API token missing or invalid from #{request.remote_ip}")
      render json: { error: 'unauthorized' }, status: :unauthorized
      nil
    end

    def provided_api_token
      header = request.headers['Authorization'].to_s.strip
      bearer = header.sub(/\ABearer\s+/i, '').strip.presence if header.match?(/\ABearer\s+/i)
      bearer || request.headers['X-Api-Key'].presence
    end

    def token_matches?(provided, expected)
      provided.present? &&
        expected.present? &&
        provided.bytesize == expected.bytesize &&
        ActiveSupport::SecurityUtils.secure_compare(provided, expected)
    end
  end
end
