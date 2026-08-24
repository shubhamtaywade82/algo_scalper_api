# frozen_string_literal: true

# Immutable market tick used as the domain boundary for market-data reads.
MarketTick = Data.define(:segment, :security_id, :ltp, :timestamp, :oi, :oi_change, :bid, :ask, :volume, :prev_close) do
  # Redis-backed tick storage keeps entries for 24h, so a tick pulled through the cache can be a
  # residual from a security_id's last active period rather than a live price. Callers that need
  # a real-time fill (order entry, not just a display quote) must check this before trusting ltp.
  def fresh?(max_age_seconds = 5)
    ts = timestamp.is_a?(Time) ? timestamp : Time.zone.parse(timestamp.to_s)
    ts.present? && (Time.current - ts) <= max_age_seconds
  rescue StandardError
    false
  end
end
