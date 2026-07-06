# frozen_string_literal: true

module Options
  # In-process registry pointing at the already-running per-index
  # Options::ChainWatchService instances (one per NIFTY/BANKNIFTY/SENSEX,
  # created once at daemon boot in lib/trading_system/bootstrap.rb).
  #
  # Exists so consumers that need live chain data (e.g. entry guards) can
  # reach the running instance's current snapshot without constructing a
  # fresh, unstarted ChainWatchService of their own.
  class ChainWatchRegistry
    @services = {}
    @mutex = Mutex.new

    class << self
      def register(index_key, service)
        @mutex.synchronize { @services[index_key.to_s.upcase] = service }
      end

      def snapshot_for(index_key)
        service = @mutex.synchronize { @services[index_key.to_s.upcase] }
        return nil unless service

        service.snapshot
      rescue StandardError => e
        Rails.logger.warn("[ChainWatchRegistry] snapshot_for(#{index_key}) failed: #{e.class} - #{e.message}")
        nil
      end

      # Test-only: clears registered services between examples.
      def reset!
        @mutex.synchronize { @services = {} }
      end
    end
  end
end
