# frozen_string_literal: true

require 'singleton'

module Providers
  # Distributed lock mechanism to prevent concurrent Ollama requests
  #
  # Prevents:
  #   - Parallel chat inference calls
  #   - Mixing chat + embeddings concurrently
  #   - Overloading the Ollama server
  #
  # Usage:
  #   return if Providers::OllamaBusy.locked?
  #
  #   Providers::OllamaBusy.with_lock do
  #     result = Providers::OllamaClient.generate(prompt)
  #   end
  #
  # Or simplest approach:
  #   sleep 0.5 between calls
  class OllamaBusy
    include Singleton

    REDIS_KEY = 'ollama:busy'
    LOCK_TTL_SECONDS = 30 # Auto-release lock after 30s if process crashes

    def initialize
      @redis = Redis.new(url: ENV.fetch('REDIS_URL', 'redis://127.0.0.1:6379/0'))
    rescue StandardError => e
      Rails.logger.error("[OllamaBusy] Redis init error: #{e.class} - #{e.message}")
      @redis = nil
    end

    # Check if Ollama is currently busy (lock exists)
    #
    # @return [Boolean] true if locked, false otherwise
    def locked?
      return false unless @redis

      @redis.exists?(REDIS_KEY) == 1
    rescue StandardError => e
      Rails.logger.error("[OllamaBusy] Lock check error: #{e.class} - #{e.message}")
      false
    end

    # Acquire lock and execute block, then release
    #
    # @param timeout_seconds [Integer] Max wait time to acquire lock (default: 5)
    # @yield Block to execute while lock is held
    # @return [Object] Return value of block, or nil if lock acquisition failed
    def with_lock(timeout_seconds: 5)
      return yield unless @redis

      acquired = acquire_lock(timeout_seconds: timeout_seconds)
      return nil unless acquired

      begin
        yield
      ensure
        release_lock
      end
    rescue StandardError => e
      Rails.logger.error("[OllamaBusy] with_lock error: #{e.class} - #{e.message}")
      release_lock
      nil
    end

    # Force release lock (use with caution)
    #
    # @return [Boolean] true if released, false otherwise
    def release_lock
      return false unless @redis

      @redis.del(REDIS_KEY)
      true
    rescue StandardError => e
      Rails.logger.error("[OllamaBusy] Release lock error: #{e.class} - #{e.message}")
      false
    end

    class << self
      delegate :locked?, :with_lock, :release_lock, to: :instance
    end

    private

    # Acquire distributed lock using Redis SET NX EX
    #
    # @param timeout_seconds [Integer] Max wait time
    # @return [Boolean] true if acquired, false otherwise
    def acquire_lock(timeout_seconds: 5)
      deadline = Time.current + timeout_seconds

      loop do
        # SET key value NX EX ttl - atomic lock acquisition
        acquired = @redis.set(REDIS_KEY, Time.current.to_i, nx: true, ex: LOCK_TTL_SECONDS)

        return true if acquired
        return false if Time.current >= deadline

        sleep 0.1 # Small delay before retry
      end
    rescue StandardError => e
      Rails.logger.error("[OllamaBusy] Acquire lock error: #{e.class} - #{e.message}")
      false
    end
  end
end
