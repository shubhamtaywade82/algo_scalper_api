# frozen_string_literal: true

require 'concurrent/map'
require 'singleton'

class TickCache
  include Singleton

  def initialize
    @map = Concurrent::Map.new
  end

  def put(tick)
    key = cache_key(tick[:segment], tick[:security_id])
    existing = @map[key]

    if existing
      # Merge new tick data into existing, keeping latest values
      # This handles cases where we receive multiple packets (ticker, prev_close, quote, OI, etc.)
      # for the same instrument in quote/full mode
      merged = existing.dup

      # Merge all fields from new tick into existing
      tick.each do |k, v|
        next if v.nil? # Skip nil values

        case k
        when :ts
          # For timestamp, prefer newer value
          merged[k] = v if merged[k].nil? || v > merged[k]
        when :kind
          # Keep track of all kinds received, but prefer most recent for primary kind
          # Store all kinds in an array or just keep latest
          merged[:kinds] ||= [merged[:kind]].compact
          merged[:kinds] << v unless merged[:kinds].include?(v)
          merged[k] = v # Use latest kind as primary
        when :segment, :security_id
          # Never change these - they're the key
          next
        else
          # For all other fields, update with new value
          # This includes: ltp, prev_close, oi, oi_prev, vol, atp, day_open, day_high, day_low, day_close, bid, ask, etc.
          merged[k] = v
        end
      end

      @map[key] = merged
    else
      @map[key] = tick.dup
    end

    Live::FeedHealthService.instance.mark_success!(:ticks)
  end

  def fetch(segment, security_id)
    @map[cache_key(segment, security_id)]
  end

  def ltp(segment, security_id)
    fetch(segment, security_id)&.dig(:ltp)
  end

  delegate :clear, to: :@map

  # Return a snapshot of all cached ticks as a plain Hash
  def all
    snapshot = {}
    @map.each_pair { |k, v| snapshot[k] = v }
    snapshot
  end

  private

  def cache_key(segment, security_id)
    "#{segment}:#{security_id}"
  end
end
