# frozen_string_literal: true

# Immutable market tick used as the domain boundary for market-data reads.
MarketTick = Data.define(:segment, :security_id, :ltp, :timestamp, :oi, :oi_change, :bid, :ask, :volume, :prev_close) do
  # Redis-backed tick storage keeps entries for 24h, so a tick pulled through the cache can be a
  # residual from a security_id's last active period rather than a live price. Callers that need
  # a real-time fill (order entry, not just a display quote) must check freshness before trusting ltp.
  #
  # Tri-state freshness (error-handling review 2026-09) — "old" and "broken"
  # are different operational states and must not collapse into one boolean:
  #
  #   :fresh   timestamp present, parseable and within +max_age_seconds+
  #   :stale   timestamp present and parseable but older than the window
  #   :invalid timestamp missing/unparseable (residual cache junk, corrupt payload)
  #
  # @return [Symbol] :fresh, :stale or :invalid
  def freshness(max_age_seconds = 5)
    ts = timestamp.is_a?(Time) ? timestamp : Time.zone.parse(timestamp.to_s)
    return :invalid if ts.blank?

    (Time.current - ts) <= max_age_seconds ? :fresh : :stale
  rescue StandardError
    :invalid
  end

  # True only for a genuinely fresh tick. A malformed timestamp is NOT fresh
  # (same outcome as before) — but it is now distinguishable via #freshness /
  # #invalid? so callers can log/alert on bad data instead of quietly
  # treating it as "just an old tick".
  #
  # @return [Boolean]
  def fresh?(max_age_seconds = 5)
    freshness(max_age_seconds) == :fresh
  end

  # @return [Boolean] timestamp parseable but older than the window
  def stale?(max_age_seconds = 5)
    freshness(max_age_seconds) == :stale
  end

  # @return [Boolean] timestamp missing or unparseable — data-quality problem
  def invalid?
    freshness == :invalid
  end
end
