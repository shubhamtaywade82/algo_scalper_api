# frozen_string_literal: true

# Stores and retrieves pre-computed analysis results from Redis cache.
# Analysis is computed by AnalysisJob in the background.
#
# Storage layout (all in Rails.cache / Redis):
#   analysis_store:NIFTY:smc       → { data: ..., computed_at: ..., valid_until: ... }
#   analysis_store:NIFTY:ai        → { data: ..., computed_at: ..., valid_until: ... }
#   analysis_store:NIFTY:regime    → { data: ..., computed_at: ..., valid_until: ... }
#
class AnalysisStore
  COMPONENTS = %i[smc ai regime].freeze

  # TTLs — how long each component stays valid
  TTLS = {
    smc:    3.minutes,
    ai:     10.minutes,
    regime: 2.minutes
  }.freeze

  # Hard expiry — cache entry auto-deleted after this (allows stale reads for a buffer)
  HARD_EXPIRY_BUFFER = 5.minutes

  class << self
    # Read a single component for an index
    def read(index_key, component)
      entry = Rails.cache.read(cache_key(index_key, component))
      return nil unless entry

      age = Time.current - Time.parse(entry[:computed_at])
      ttl = TTLS[component.to_sym] || 5.minutes

      {
        data: entry[:data],
        validity: {
          cached: true,
          computed_at: entry[:computed_at],
          valid_until: entry[:valid_until],
          age_seconds: age.round(0),
          ttl_seconds: ttl.to_i,
          fresh: age < ttl
        }
      }
    rescue StandardError => e
      Rails.logger.warn("[AnalysisStore] read error for #{index_key}:#{component}: #{e.message}")
      nil
    end

    # Write a component result
    def write(index_key, component, data)
      ttl = TTLS[component.to_sym] || 5.minutes
      now = Time.current

      entry = {
        data: data,
        computed_at: now.iso8601,
        valid_until: (now + ttl).iso8601
      }

      Rails.cache.write(
        cache_key(index_key, component),
        entry,
        expires_in: ttl + HARD_EXPIRY_BUFFER
      )
    rescue StandardError => e
      Rails.logger.error("[AnalysisStore] write error for #{index_key}:#{component}: #{e.message}")
    end

    # Read all components for an index (used by the API)
    def read_all(index_key)
      COMPONENTS.to_h { |c| [c, read(index_key, c)] }
    end

    # Check if a component needs refresh
    def stale?(index_key, component)
      entry = Rails.cache.read(cache_key(index_key, component))
      return true unless entry

      age = Time.current - Time.parse(entry[:computed_at])
      ttl = TTLS[component.to_sym] || 5.minutes
      age >= ttl
    rescue StandardError
      true
    end

    # Check which components need refresh for an index
    def stale_components(index_key)
      COMPONENTS.select { |c| stale?(index_key, c) }
    end

    private

    def cache_key(index_key, component)
      "analysis_store:#{index_key}:#{component}"
    end
  end
end
