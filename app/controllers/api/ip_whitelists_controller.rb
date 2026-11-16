# frozen_string_literal: true

module Api
  # Re-registers this machine's public IP on Dhan's order whitelist.
  class IpWhitelistsController < ApplicationController
    include Api::TokenAuthenticatable

    before_action :authenticate_settings_token!

    # PATCH /api/settings/ip_whitelist
    # Detects the current public IPv4 and attempts to whitelist it on Dhan.
    def update
      info = Dhan::IpService.fetch_ip_info
      ip = info[:public_ipv4]

      if ip.blank? || ip == 'Unknown'
        render json: { success: false, error: 'Could not detect current public IPv4' }
        return
      end

      render json: Dhan::IpService.update_ip(ip)
    rescue StandardError => e
      Rails.logger.error("[IpWhitelistsController] update error: #{e.class} - #{e.message}")
      render json: { error: e.message }, status: :internal_server_error
    end
  end
end
