# frozen_string_literal: true

module Dhan
  class IpService
    def self.fetch_ip_info
      new.fetch_ip_info
    end

    def self.update_ip(ip)
      new.update_ip(ip)
    end

    # Fetches public IPs + registered slots only. Does not write {PublicIpLog} (hot paths: dashboard, health).
    def fetch_ip_info
      # Ensure DhanHQ is configured with latest token
      DhanHQ.configure { |c| c.access_token = Dhan::TokenManager.current_token }

      # Clear memoized cache to ensure fresh detection on every health check
      DhanHQ::Utils::NetworkInspector.reset_cache!

      v4 = fetch_public_ipv4
      v6 = fetch_public_ipv6

      {
        public_ipv4: v4,
        public_ipv6: v6,
        registered_ips: fetch_registered_ips
      }
    rescue StandardError => e
      Rails.logger.error("[Dhan::IpService] Error fetching IP info: #{e.message}")
      { public_ipv4: 'Unknown', public_ipv6: 'Unknown', registered_ips: nil }
    end

    # Background / scheduled audit: persist last-seen IPs with {PublicIpLog::RECENT_TOUCH_COOLDOWN} throttle.
    def self.audit_public_ips!
      info = fetch_ip_info
      persist_public_ip_logs(info)
      info
    end

    def self.persist_public_ip_logs(info)
      PublicIpLog.log_ip(info[:public_ipv4], 'v4')
      PublicIpLog.log_ip(info[:public_ipv6], 'v6')
    end

    def update_ip(ip_to_whitelist)
      return { success: false, error: 'IP is blank' } if ip_to_whitelist.blank?

      # Ensure DhanHQ is configured
      DhanHQ.configure { |c| c.access_token = Dhan::TokenManager.current_token }

      status = fetch_registered_ips
      return { success: false, error: 'Could not fetch registered IPs' } unless status

      # Check if already whitelisted
      if [status[:primary_ip], status[:secondary_ip]].include?(ip_to_whitelist)
        return { success: true, message: 'Already whitelisted' }
      end

      # Determine which slot to update based on modification dates
      today = Time.zone.today

      primary_date = parse_dhan_date(status[:modification_allowed_date_for_primary_ip])
      secondary_date = parse_dhan_date(status[:modification_allowed_date_for_secondary_ip])

      # Logic: Prefer Primary if available, otherwise Secondary
      target_flag = nil
      if primary_date && today >= primary_date
        target_flag = 'PRIMARY'
      elsif secondary_date && today >= secondary_date
        target_flag = 'SECONDARY'
      end

      if target_flag
        Rails.logger.info("[Dhan::IpService] Updating #{target_flag} IP to #{ip_to_whitelist}")
        res = DhanHQ::Resources::IPSetup.new.update(ip: ip_to_whitelist, ip_flag: target_flag)

        if res && (res['status'] == 'success' || res[:status] == 'success')
          Rails.logger.info("[Dhan::IpService] Successfully updated #{target_flag} to #{ip_to_whitelist}")
          { success: true, flag: target_flag }
        else
          msg = res['message'] || res[:message] || 'API Error'
          Rails.logger.error("[Dhan::IpService] API Error updating #{target_flag}: #{msg}")
          { success: false, error: msg }
        end
      else
        { success: false, error: 'Modification cooldown active for both slots' }
      end
    end

    private

    def fetch_public_ipv4
      ip = DhanHQ::Utils::NetworkInspector.public_ipv4
      ip == 'unknown' ? 'Unknown' : ip
    rescue StandardError => e
      Rails.logger.warn("[Dhan::IpService] Failed to fetch public IPv4: #{e.message}")
      'Unknown'
    end

    def fetch_public_ipv6
      ip = DhanHQ::Utils::NetworkInspector.public_ipv6
      return 'Unknown' if ip == 'unknown'
      return 'None' if ip == DhanHQ::Utils::NetworkInspector.public_ipv4 && ip.exclude?(':')

      ip
    rescue StandardError => e
      Rails.logger.warn("[Dhan::IpService] Failed to fetch public IPv6: #{e.message}")
      'Unknown'
    end

    def fetch_registered_ips
      raw = DhanHQ::Resources::IPSetup.new.current
      return nil unless raw.is_a?(Hash)

      # Map to standardized field names used by frontend
      {
        primary_ip: raw['primaryIP'],
        secondary_ip: raw['secondaryIP'],
        modification_allowed_date_for_primary_ip: raw['modifyDatePrimary'],
        modification_allowed_date_for_secondary_ip: raw['modifyDateSecondary']
      }
    rescue StandardError => e
      Rails.logger.warn("[Dhan::IpService] Failed to fetch registered IPs from DhanHQ: #{e.message}")
      nil
    end

    def parse_dhan_date(date_str)
      return nil if date_str.blank?
      Date.parse(date_str)
    rescue ArgumentError
      nil
    end
  end
end
