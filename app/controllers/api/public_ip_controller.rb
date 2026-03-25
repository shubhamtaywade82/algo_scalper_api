# frozen_string_literal: true

module Api
  # On-demand public IP audit (same as {PublicIpLogJob}). Prefer the recurring job for normal use.
  class PublicIpController < ApplicationController
    def audit
      info = Dhan::IpService.audit_public_ips!
      render json: {
        public_ipv4: info[:public_ipv4],
        public_ipv6: info[:public_ipv6],
        registered_ips: info[:registered_ips]
      }
    end
  end
end
