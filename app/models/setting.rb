# frozen_string_literal: true

class Setting < ApplicationRecord
  validates :key, presence: true, uniqueness: true

  # Cached read
  def self.fetch(key, default = nil, ttl: 30)
    Rails.cache.fetch("setting:#{key}", expires_in: ttl.seconds) do
      find_by(key:)&.value || default
    end
  end

  # Write + cache bust
  def self.put(key, value)
    rec = find_or_initialize_by(key:)
    rec.value = value.to_s
    rec.save!
    Rails.cache.delete("setting:#{key}")
    value
  end

  # Typed helpers (quality of life)
  def self.fetch_i(key, default = 0) = fetch(key, default).to_i
  def self.fetch_f(key, default = 0.0) = fetch(key, default).to_f

  def self.fetch_bool(key, default = false) # rubocop:disable Style/OptionalBooleanParameter,Naming/PredicateMethod
    raw = fetch(key, default)
    return !!raw if [true, false].include?(raw)

    %w[1 true yes on].include?(raw.to_s.strip.downcase)
  end
end


