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
  # Never queried by value (only .active's expiry_time filter), so randomized encryption
  # is fine and stronger than deterministic.
  encrypts :token, deterministic: false

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
      # Cache only the id, not the record: Rails.cache is Solid Cache (Postgres-backed) in
      # this project, and caching the full instance would serialize the decrypted token
      # into a second table, defeating the point of encrypting the column at all.
      id = Rails.cache.fetch(CACHE_KEY, expires_in: CACHE_TTL) do
        where('expiry_time > ?', Time.current).order(expiry_time: :desc).first&.id
      end
      return nil unless id

      find_by(id: id)
    end

    def valid?
      active.present?
    end

    def clear_active_cache
      Rails.cache.delete(CACHE_KEY)
    end
  end

  after_commit :clear_active_cache, on: :create

  private

  def clear_active_cache
    self.class.clear_active_cache
  end
end

