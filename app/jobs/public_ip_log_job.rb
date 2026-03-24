# frozen_string_literal: true

# Persists public IP last-seen via {Dhan::IpService.audit_public_ips!} on a schedule.
# Dashboard and health checks use {Dhan::IpService.fetch_ip_info} only (no DB writes).
class PublicIpLogJob < ApplicationJob
  queue_as :background

  def perform
    Dhan::IpService.audit_public_ips!
  rescue StandardError => e
    Rails.logger.error("[PublicIpLogJob] #{e.class} - #{e.message}")
  end
end
