# frozen_string_literal: true

module Entries
  # Postgres session-level advisory lock keyed by index (NIFTY/BANKNIFTY/SENSEX).
  # Serializes the guard-pipeline decision + PositionTracker.create! so two
  # concurrent try_enter calls for the same index can't both pass exposure/
  # max-concurrent/daily-limit checks before either commits (TOCTOU race).
  module AdvisoryLock
    LOCK_NAMESPACE = 0x454E5452 # 'ENTR' — arbitrary namespace to avoid key collisions with other advisory locks

    module_function

    def with_index_lock(index_key)
      key = lock_key(index_key)
      ActiveRecord::Base.connection_pool.with_connection do |conn|
        conn.execute("SELECT pg_advisory_lock(#{LOCK_NAMESPACE}, #{key})")
        begin
          yield
        ensure
          conn.execute("SELECT pg_advisory_unlock(#{LOCK_NAMESPACE}, #{key})")
        end
      end
    end

    def lock_key(index_key)
      Zlib.crc32(index_key.to_s) & 0x7FFFFFFF
    end
  end
end
