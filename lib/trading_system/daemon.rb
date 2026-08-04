# frozen_string_literal: true

module TradingSystem
  # Separate-process daemon for running long-lived trading services.
  #
  # This is intentionally decoupled from the web server lifecycle so trading
  # can be restarted/monitored independently of Puma.
  class Daemon
    def self.start(...)
      new.start(...)
    end

    def initialize(supervisor: nil)
      @supervisor = supervisor
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

      if market_closed
        Rails.logger.info('[TradingDaemon] Market closed - starting WebSocket only')
        @supervisor[:market_feed]&.start
        Rails.logger.info('[Supervisor] started market_feed (WebSocket only)')
        return
      end

      @supervisor.start_all
      subscribe_active_positions!
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

    def trap_signals!
      %w[INT TERM].each do |sig|
        Signal.trap(sig) do
          Rails.logger.info("[TradingDaemon] Received #{sig}, shutting down...")
          safe_stop!
          exit(0) # rubocop:disable Rails/Exit
        end
      end

      at_exit { safe_stop! }
    end

    def safe_stop!
      @supervisor&.stop_all
    rescue StandardError => e
      Rails.logger.error("[TradingDaemon] stop_all failed: #{e.class} - #{e.message}")
    end

    def keep_process_alive!
      sleep
    end
  end
end

