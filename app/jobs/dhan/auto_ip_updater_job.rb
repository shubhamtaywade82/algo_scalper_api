# frozen_string_literal: true

module Dhan
  class AutoIpUpdaterJob < ApplicationJob
    queue_as :default

    def perform
      return unless auto_update_enabled?

      info = Dhan::IpService.fetch_ip_info
      v4 = info[:public_ipv4]
      v6 = info[:public_ipv6]
      registered = info[:registered_ips]

      return unless registered

      # Check IPv4 first
      if v4.present? && v4 != 'Unknown' && ![registered[:primary_ip], registered[:secondary_ip]].include?(v4)
        attempt_update(v4, 'v4')
      # Then check IPv6 if it's actually an IPv6 address
      elsif v6.present? && v6 != 'Unknown' && v6 != 'None' && v6.include?(':') && ![registered[:primary_ip], registered[:secondary_ip]].include?(v6)
        attempt_update(v6, 'v6')
      end
    end

    private

    def auto_update_enabled?
      AlgoConfig.fetch.dig(:risk, :auto_update_ip) == true
    end

    def attempt_update(ip, version)
      Rails.logger.info("[Dhan::AutoIpUpdaterJob] Attempting auto-update for #{version} IP: #{ip}")
      result = Dhan::IpService.update_ip(ip)

      if result[:success]
        msg = "🚀 [DHAN] Auto-updated #{result[:flag]} whitelisted IP to #{ip} (#{version})"
        Rails.logger.info(msg)
        TelegramNotifier.notify(msg) if defined?(TelegramNotifier)
      else
        Rails.logger.warn("[Dhan::AutoIpUpdaterJob] Auto-update failed for #{ip}: #{result[:error]}")
      end
    end
  end
end
