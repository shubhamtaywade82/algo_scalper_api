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

require 'rails_helper'

RSpec.describe PublicIpLog do
  include ActiveSupport::Testing::TimeHelpers

  describe '.log_ip' do
    it 'creates a row on first sight' do
      described_class.log_ip('203.0.113.1', 'v4')
      row = described_class.find_by(ip_address: '203.0.113.1', ip_version: 'v4')
      expect(row).to be_present
      expect(row.last_seen_at).to be_present
    end

    it 'does not touch DB when same IP was seen within cooldown' do
      travel_to Time.zone.parse('2026-03-23 10:00:00') do
        described_class.log_ip('203.0.113.2', 'v4')
      end
      first_seen = described_class.find_by(ip_address: '203.0.113.2').updated_at

      travel_to Time.zone.parse('2026-03-23 10:05:00') do
        described_class.log_ip('203.0.113.2', 'v4')
      end

      expect(described_class.find_by(ip_address: '203.0.113.2').updated_at).to eq(first_seen)
    end

    it 'updates last_seen when same IP after cooldown' do
      travel_to Time.zone.parse('2026-03-23 10:00:00') do
        described_class.log_ip('203.0.113.3', 'v4')
      end

      travel_to Time.zone.parse('2026-03-23 10:20:00') do
        described_class.log_ip('203.0.113.3', 'v4')
      end

      row = described_class.find_by(ip_address: '203.0.113.3')
      expect(row.last_seen_at).to be_within(1.second).of(Time.zone.parse('2026-03-23 10:20:00'))
    end
  end
end
