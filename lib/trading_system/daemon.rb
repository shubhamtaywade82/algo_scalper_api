# frozen_string_literal: true

module TradingSystem
  # Separate-process daemon for running long-lived trading services.
  #
  # This is intentionally decoupled from the web server lifecycle so trading
  # can be restarted/monitored independently of Puma.
  #
  # If started while market is closed, only the WebSocket feed runs until market
  # opens; a background thread then starts the remaining services automatically.
  class Daemon
    MARKET_OPEN_POLL_INTERVAL = 60 # seconds

    def self.start(...)
      new.start(...)
    end

    def initialize(supervisor: nil)
      @supervisor = supervisor
      @market_open_thread = nil
    end

    def start(keep_alive: true, allow_in_test: false)
      return false unless enabled?(allow_in_test: allow_in_test)

      setup_supervisor!
      trap_signals!

      start_services!

      Rails.logger.info('[TradingDaemon] Started')

      keep_process_alive! if keep_alive
      true
    rescue StandardError => e
      Notifications::TelegramNotifier.instance.notify_error("#{e.class} - #{e.message}", context: 'TradingSystem::Daemon')
      Rails.logger.error("[TradingDaemon] #{e.class} - #{e.message}")
      safe_stop!
      false
    end

    private

    def enabled?(allow_in_test:)
      return false if Rails.env.test? && !allow_in_test
      return false if ENV['BACKTEST_MODE'] == '1' || ENV['SCRIPT_MODE'] == '1'
      return false if ENV['DISABLE_TRADING_SERVICES'] == '1'

      ENV['ENABLE_TRADING_SERVICES'].to_s == 'true'
    end

    def setup_supervisor!
      @supervisor ||= Rails.application.config.x.trading_supervisor
      @supervisor ||= TradingSystem::Bootstrap.build_supervisor

      Rails.application.config.x.trading_supervisor = @supervisor
    end

    def start_services!
      market_closed = TradingSession::Service.market_closed?

      TradingSystem::Bootstrap.boot_reconciliation!(strict: strict_boot_reconciliation?(market_closed: market_closed))

      if market_closed
        Rails.logger.info('[TradingDaemon] Market closed - starting WebSocket only; will start full services when market opens')
        @supervisor[:market_feed]&.start
        Rails.logger.info('[Supervisor] started market_feed (WebSocket only)')
        start_market_open_poller!
        return
      end

      @supervisor.start_all
      subscribe_active_positions!
    end

    def start_market_open_poller!
      @market_open_thread = Thread.new do
        Thread.current.name = 'daemon-market-open-poller'
        loop do
          sleep MARKET_OPEN_POLL_INTERVAL
          next if TradingSession::Service.market_closed?

          Rails.logger.info('[TradingDaemon] Market opened - starting remaining services')
          @supervisor.start_all
          subscribe_active_positions!
          Rails.logger.info('[TradingDaemon] Full services started')
          break
        end
      end
    end

    def subscribe_active_positions!
      active_pairs = Live::PositionIndex.instance.all_keys.map do |k|
        seg, sid = k.split(':', 2)
        { segment: seg, security_id: sid }
      end

      @supervisor[:market_feed].subscribe_many(active_pairs) if active_pairs.any?
    rescue StandardError => e
      Rails.logger.error("[TradingDaemon] subscribe_active_positions failed: #{e.class} - #{e.message}")
    end

    def strict_boot_reconciliation?(market_closed:)
      # Default strict behavior only when market is open.
      default_strict = !market_closed
      return default_strict if ENV['TRADING_BOOT_RECONCILIATION_STRICT'].blank?

      ENV['TRADING_BOOT_RECONCILIATION_STRICT'].to_s.downcase == 'true'
    end

    def trap_signals!
      @shutdown_requested = nil
      %w[INT TERM].each do |sig|
        Signal.trap(sig) do
          @shutdown_requested = sig
        end
      end

      # Still keep at_exit as a fallback for other types of termination
      at_exit { safe_stop! }
    end

    def safe_stop!
      # Guard against multiple calls
      return if @stopping
      @stopping = true

      if @market_open_thread&.alive?
        @market_open_thread.kill
        @market_open_thread = nil
      end

      if @supervisor
        begin
          @supervisor.stop_all
        rescue StandardError => e
          warn "[TradingDaemon] stop_all failed: #{e.class} - #{e.message}"
        end
      end
    rescue StandardError => e
      warn "[TradingDaemon] safe_stop! failed: #{e.class} - #{e.message}"
    end

    def keep_process_alive!
      loop do
        if @shutdown_requested
          Rails.logger.info("[TradingDaemon] Received #{@shutdown_requested}, shutting down...")
          safe_stop!
          break
        end
        sleep 1
      end
    end
  end
end
