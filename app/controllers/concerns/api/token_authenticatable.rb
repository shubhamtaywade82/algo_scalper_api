# frozen_string_literal: true

module Api
  # Optional Bearer / X-Api-Key checks for dashboard vs operator API tiers.
  #
  # When +API_DASHBOARD_TOKEN+ or +API_OPERATOR_TOKEN+ is unset, the corresponding
  # check is skipped in non-production (local convenience). In production, unset
  # tokens return 503 so the API does not run effectively open.
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

      if Rails.env.production? && expected.blank?
        Rails.logger.error(
          "[#{self.class.name}] #{tier} API token env not set in production — refusing request"
        )
        render json: { error: 'api_token_unconfigured', tier: tier.to_s }, status: :service_unavailable
        return nil
      end

      return if expected.blank?
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
