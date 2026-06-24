# frozen_string_literal: true

module Orders
  class TokenBucket
    class RateLimited < StandardError
    end

    def initialize(rate:, per: 1.second)
      @rate = rate.to_f
      @per = per.to_f
      @tokens = @rate
      @last_refill = monotonic_time
      @mutex = Mutex.new
    end

    def consume!(timeout: 0.05)
      deadline = monotonic_time + timeout
      loop do
        @mutex.synchronize { refill! }
        return yield if @mutex.synchronize { consume_one! }

        break if monotonic_time >= deadline

        sleep(0.001)
      end

      raise RateLimited, "rate limit #{@rate} req/#{(@per * 1000).to_i}ms exceeded"
    end

    private

    def refill!
      now = monotonic_time
      elapsed = now - @last_refill
      @tokens = [@rate, @tokens + (@rate * elapsed / @per)].min
      @last_refill = now
    end

    def consume_one!
      return false if @tokens < 1

      @tokens -= 1
      true
    end

    def monotonic_time
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end
end
