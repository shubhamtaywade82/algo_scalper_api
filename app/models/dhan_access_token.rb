# == Schema Information
#
# Table name: dhan_access_tokens
#
#  id          :integer          not null, primary key
#  token       :string           not null
#  expiry_time :datetime         not null
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#
# Indexes
#
#  index_dhan_access_tokens_on_expiry_time  (expiry_time)
#

# frozen_string_literal: true

class DhanAccessToken < ApplicationRecord
  CACHE_KEY = 'dhan_access_token/active'
  CACHE_TTL = 30.seconds

  def expired?
    expiry_time <= Time.current
  end

  def expiring_soon?(buffer_minutes: 30)
    expiry_time <= buffer_minutes.minutes.from_now
  end

  class << self
    def active
      Rails.cache.fetch(CACHE_KEY, expires_in: CACHE_TTL) do
        where('expiry_time > ?', Time.current).order(expiry_time: :desc).first
      end
    end

    def valid?
      active.present?
    end

    def clear_active_cache
      Rails.cache.delete(CACHE_KEY)
    end
  end

  after_create :clear_active_cache

  private

  def clear_active_cache
    self.class.clear_active_cache
  end
end

