# frozen_string_literal: true

module Api
  # Optional Bearer / X-Api-Key checks for dashboard vs operator API tiers.
  #
  # When +API_DASHBOARD_TOKEN+ or +API_OPERATOR_TOKEN+ is unset, the check is skipped
  # only when +Rails.env.local?+ (+development+ / +test+). Staging, production, and
  # any other env require
  # an explicit token (503 when unset) so the API does not run effectively open.
  module TokenAuthenticatable
    extend ActiveSupport::Concern

    private

    def authenticate_dashboard_token!
      require_api_token!(ENV.fetch('API_DASHBOARD_TOKEN', nil), tier: :dashboard)
    end

    def authenticate_operator_token!
      require_api_token!(ENV.fetch('API_OPERATOR_TOKEN', nil), tier: :operator)
    end

    def authenticate_settings!
      return if Rails.env.development?

      if Rails.env.production? && ENV['SETTINGS_UPDATE_TOKEN'].blank?
        Rails.logger.error(
          "[#{self.class.name}] SETTINGS_UPDATE_TOKEN must be set in production for settings updates"
        )
        render json: { error: 'settings_update_unconfigured' }, status: :service_unavailable
        return
      end

      expected = ENV['SETTINGS_UPDATE_TOKEN'].presence
      return if expected.nil?

      provided = request.headers['X-Settings-Update-Token'].presence || params[:token].presence
      if provided && token_matches?(provided, expected)
        return
      end

      render json: { error: 'unauthorized' }, status: :unauthorized
    end

    def require_api_token!(expected, tier:)
      expected = expected.presence

      if expected.blank?
        unless api_token_optional_when_unset?
          Rails.logger.error(
            "[#{self.class.name}] #{tier} API token env not set — refusing request " \
            "(#{Rails.env})"
          )
          render json: { error: 'api_token_unconfigured', tier: tier.to_s }, status: :service_unavailable
          return
        end

        return
      end

      return if token_matches?(provided_api_token, expected)

      Rails.logger.warn("[#{self.class.name}] #{tier} API token missing or invalid from #{request.remote_ip}")
      render json: { error: 'unauthorized' }, status: :unauthorized
    end

    def provided_api_token
      header = request.headers['Authorization'].to_s.strip
      bearer = header.sub(/\ABearer\s+/i, '').strip.presence if header.match?(/\ABearer\s+/i)
      bearer || request.headers['X-Api-Key'].presence
    end

    def token_matches?(provided, expected)
      p = provided.to_s
      e = expected.to_s
      p.present? &&
        e.present? &&
        p.bytesize == e.bytesize &&
        ActiveSupport::SecurityUtils.secure_compare(p, e)
    end

    def api_token_optional_when_unset?
      Rails.env.local?
    end
  end
end
