# frozen_string_literal: true

require 'fileutils'

module Strategies
  # Per-strategy tagged logging: file + Redis ring buffer + ActionCable broadcast.
  #
  # Usage:
  #   stream = Strategies::LogStream.new("supertrend_v1")
  #   stream.log(:info, "Starting session")
  #   Strategies::LogStream.fetch("supertrend_v1", limit: 50) # => [["ts","INFO","line"], ...]
  class LogStream
    LOG_DIR = Rails.root.join("log/strategies")
    RING_KEY_PREFIX = "strategy_logs:"
    RING_MAXLEN = 1000

    def initialize(slug)
      @slug = slug
      @mutex = Mutex.new
      ensure_log_dir
    end

    def log(level, message)
      timestamp = Time.current.iso8601(3)
      level_str = level.to_s.upcase
      line = "[#{timestamp}] [#{level_str}] #{message}"

      write_file(line)
      push_ring(timestamp, level_str, message)
      broadcast(timestamp, level_str, message)
    end

    def info(msg)  = log(:info, msg)
    def warn(msg)  = log(:warn, msg)
    def error(msg) = log(:error, msg)

    def self.fetch(slug, limit: 100)
      redis.with do |conn|
        conn.lrange("#{RING_KEY_PREFIX}#{slug}", 0, limit - 1).map do |entry|
          JSON.parse(entry)
        rescue JSON::ParserError
          ["", "UNKNOWN", entry]
        end
      end
    end

    private

  def write_file(line)
    path = LOG_DIR.join("#{@slug}.log")
    @mutex.synchronize do
      File.open(path, "a") { |f| f.puts(line) }
    end
  end

  def push_ring(ts, level, message)
    entry = JSON.generate([ts, level, message])
    self.class.redis.with do |conn|
      conn.lpush("#{RING_KEY_PREFIX}#{@slug}", entry)
      conn.ltrim("#{RING_KEY_PREFIX}#{@slug}", 0, RING_MAXLEN - 1)
    end
  rescue StandardError => e
    Rails.logger.warn("[LogStream] Redis push failed for #{@slug}: #{e.message}")
  end

  def broadcast(ts, level, message)
    ActionCable.server.broadcast("strategy_logs_#{@slug}", {
      ts: ts, level: level, line: message
    })
  rescue StandardError => e
    Rails.logger.warn("[LogStream] Broadcast failed for #{@slug}: #{e.message}")
  end

  def ensure_log_dir
    LOG_DIR.mkpath unless LOG_DIR.directory?
  end

  class << self
    def redis
      @redis ||= ConnectionPool.new(size: 2, timeout: 3) do
        Redis.new(url: ENV.fetch("REDIS_URL", "redis://127.0.0.1:6379/0"))
      end
    end
  end
  end
end
