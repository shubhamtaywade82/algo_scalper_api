# == Schema Information
#
# Table name: public_ip_logs
#
#  id            :integer          not null, primary key
#  ip_address    :string
#  ip_version    :string
#  first_seen_at :datetime
#  last_seen_at  :datetime
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#

# frozen_string_literal: true

class PublicIpLog < ApplicationRecord
  validates :ip_address, presence: true
  validates :ip_version, inclusion: { in: %w[v4 v6] }

  # Skip DB write when the same IP was recorded recently (dashboard polling / duplicate callers).
  RECENT_TOUCH_COOLDOWN = 15.minutes

  def self.log_ip(ip, version)
    return if ip.blank? || %w[Unknown None unknown].include?(ip)

    log = find_or_initialize_by(ip_address: ip, ip_version: version)
    log.first_seen_at ||= Time.current

    if log.persisted? && log.last_seen_at.present? && log.last_seen_at > RECENT_TOUCH_COOLDOWN.ago
      return log
    end

    log.last_seen_at = Time.current
    log.save! if log.changed?
    log
  end
end
