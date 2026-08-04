# frozen_string_literal: true

# Thread-safe token bucket rate limiter.
#
# Usage:
#   limiter = TokenBucket.new(rate: 10, per: 1.second)
#   limiter.consume!  # => true when a token is available, false when limit is hit
#
# Default research-doc cap: 10 requests per second.
class TokenBucket
  class Error < StandardError; end
  class RateLimited < Error; end

  attr_reader :rate, :per

  def initialize(rate: 10, per: 1.second)
    @rate = rate.to_i
    @per = per.to_f
    @tokens = rate.to_f
    @last = Time.current.to_f
    @lock = Mutex.new
  end

  # Try to consume one token. Returns true if allowed.
  def consume!
    raise ArgumentError, 'block required' unless block_given?

    lock.synchronize do
      refill!

      if @tokens < 1.0
        raise RateLimited, "rate limit reached (#{@rate}/#{per}sec)"
      end

      @tokens -= 1.0
      yield
    end
  end

  # Non-raising status.
  def allowed?
    lock.synchronize do
      refill!
      @tokens >= 1.0
    end
  end

  def status
    lock.synchronize do
      {
        rate: @rate,
        per_seconds: @per,
        tokens: @tokens.round(4),
        allowed: @tokens >= 1.0
      }
    end
  end

  private

  attr_reader :lock

  def refill!
    now = Time.current.to_f
    elapsed = now - @last
    return if elapsed <= 0

    @tokens = [@tokens + (elapsed / @per * @rate), @rate].min
    @last = now
  end
end
