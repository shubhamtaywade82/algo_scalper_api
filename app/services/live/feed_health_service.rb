# frozen_string_literal: true

require 'singleton'

module Live
  # Centralised guard for DhanHQ data feeds.
  # Tracks last successful refresh per feed and blocks trading
  # when required data is stale.
  class FeedHealthService
    include Singleton

    DEFAULT_THRESHOLDS = {
      funds: 60.seconds,
      positions: 30.seconds,
      ticks: 10.seconds
    }.freeze

    FeedStaleError = Class.new(StandardError) do
      attr_reader :feed, :last_seen_at, :threshold, :last_error

      def initialize(feed:, last_seen_at:, threshold:, last_error: nil)
        @feed = feed
        @last_seen_at = last_seen_at
        @threshold = threshold
        @last_error = last_error

        message = "#{feed} feed stale for #{stale_duration(last_seen_at, threshold)}"
        message += "; last error: #{last_error[:error]}" if last_error&.dig(:error)
        super(message)
      end

      private

      def stale_duration(last_seen_at, threshold)
        last_seen_at ? "#{(Time.current - last_seen_at).round(1)}s (> #{threshold}s)" : 'unknown duration'
      end
    end

    def initialize
      @timestamps = {}
      @failures = {}
      @threshold_overrides = {}
      @mutex = Mutex.new
    end

    def mark_success!(feed)
      with_lock do
        @timestamps[feed.to_sym] = Time.current
        @failures.delete(feed.to_sym)
      end
    end

    def mark_failure!(feed, error: nil)
      with_lock do
        @failures[feed.to_sym] = { error: error&.message, at: Time.current }
      end
    end

    def stale?(feed)
      last_seen = with_lock { @timestamps[feed.to_sym] }
      return true unless last_seen

      Time.current - last_seen > threshold_for(feed)
    end

    def assert_healthy!(feeds)
      feeds.each do |feed|
        next unless stale?(feed)

        failure = with_lock { @failures[feed.to_sym] }
        raise FeedStaleError.new(
          feed: feed,
          last_seen_at: with_lock { @timestamps[feed.to_sym] },
          threshold: threshold_for(feed),
          last_error: failure
        )
      end

      true
    end

    def threshold_for(feed)
      with_lock { threshold_value(feed) }
    end

    def configure_threshold(feed, seconds)
      with_lock do
        @threshold_overrides[feed.to_sym] = seconds
      end
    end

    def status
      feeds = DEFAULT_THRESHOLDS.keys | with_lock { (@timestamps.keys + @threshold_overrides.keys + @failures.keys) }

      feeds.each_with_object({}) do |feed, memo|
        last_seen = with_lock { @timestamps[feed.to_sym] }
        memo[feed] = {
          last_seen_at: last_seen,
          threshold: threshold_for(feed),
          stale: last_seen ? (Time.current - last_seen > threshold_for(feed)) : true,
          last_error: with_lock { @failures[feed.to_sym] }
        }
      end
    end

    private

    def with_lock(&)
      @mutex.synchronize(&)
    end

    def threshold_value(feed)
      @threshold_overrides.fetch(feed.to_sym) { DEFAULT_THRESHOLDS.fetch(feed.to_sym, 30.seconds) }
    end
  end
end
