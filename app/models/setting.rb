# == Schema Information
#
# Table name: settings
#
#  id         :integer          not null, primary key
#  key        :string           not null
#  value      :text
#  created_at :datetime         not null
#  updated_at :datetime         not null
#
# Indexes
#
#  index_settings_on_key  (key) UNIQUE
#

# frozen_string_literal: true

class Setting < ApplicationRecord
  validates :key, presence: true, uniqueness: true

  # --- Strict APIs (error-handling review 2026-09) -------------------------

  # Read a setting that MUST exist. Missing/blank is a configuration defect,
  # not a value — for trading/risk/strategy settings this fails loudly.
  #
  # @raise [Errors::ConfigurationError]
  # @return [String]
  def self.require!(key)
    raw = Rails.cache.fetch("setting:#{key}", expires_in: 30.seconds) do
      find_by(key:)&.value
    end
    raise Errors::ConfigurationError, "required Setting #{key.inspect} is missing" if raw.blank?

    raw
  end

  # Read a setting with an EXPLICIT default. The default is a keyword arg so
  # every call site states its own fallback in plain text — no invisible
  # nil/0/false materialising inside a helper.
  #
  # @return [Object] the stored value or the explicit default
  def self.optional(key, default: nil)
    Rails.cache.fetch("setting:#{key}", expires_in: 30.seconds) do
      find_by(key:)&.value || default
    end
  end

  # --- Legacy APIs ----------------------------------------------------------
  # Kept for existing callers; new code should use require!/optional.
  # AlgoSetting passes domain-defined defaults from its metadata, which is a
  # legitimate use — but do not add new implicit defaults.

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

  # Typed helpers (quality of life) — see legacy note above
  def self.fetch_i(key, default = 0) = fetch(key, default).to_i
  def self.fetch_f(key, default = 0.0) = fetch(key, default).to_f

  def self.fetch_bool(key, default = false) # rubocop:disable Style/OptionalBooleanParameter,Naming/PredicateMethod
    raw = fetch(key, default)
    return !!raw if [true, false].include?(raw)

    %w[1 true yes on].include?(raw.to_s.strip.downcase)
  end
end
