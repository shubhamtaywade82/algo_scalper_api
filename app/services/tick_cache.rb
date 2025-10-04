# frozen_string_literal: true

require "concurrent/map"
require "singleton"

class TickCache
  include Singleton

  def initialize
    @map = Concurrent::Map.new
  end

  def put(tick)
    key = cache_key(tick[:segment], tick[:security_id])
    @map[key] = tick
  end

  def fetch(segment, security_id)
    @map[cache_key(segment, security_id)]
  end

  def ltp(segment, security_id)
    fetch(segment, security_id)&.dig(:ltp)
  end

  def clear
    @map.clear
  end

  private

  def cache_key(segment, security_id)
    "#{segment}:#{security_id}"
  end
end
