# frozen_string_literal: true

require 'bigdecimal'
require 'singleton'
require 'ostruct'
require_relative '../concerns/broker_fee_calculator'
require_relative 'risk_manager_service/runner'
require_relative 'risk_manager_service/exit_enforcement'
require_relative 'risk_manager_service/exit_execution'
require_relative 'risk_manager_service/pnl_cache'
require_relative 'risk_manager_service/config'

module Live
  # Responsible for monitoring active PositionTracker entries, keeping PnL up-to-date in Redis,
  # and enforcing exits according to configured risk rules.
  #
  # Behaviour:
  # - If an external ExitEngine is provided (recommended), RiskManagerService will NOT place exits itself.
  #   Instead ExitEngine calls the enforcement methods and RiskManagerService supplies helper functions.
  # - If no external ExitEngine is provided, RiskManagerService will execute exits itself (backwards compatibility).
  class RiskManagerService
    LOOP_INTERVAL = 5
    API_CALL_STAGGER_SECONDS = 1.0

    include Runner
    include ExitEnforcement
    include ExitExecution
    include PnlCache
    include Config

    def initialize(exit_engine: nil)
      @exit_engine = exit_engine
      @mutex = Mutex.new
      @running = false
      @thread = nil
      @market_closed_checked = false # Track if we've already checked after market closed
      @watchdog_thread = nil # Initialize as nil, start watchdog only when service starts
    end

    # Start monitoring loop (non-blocking)
    def start
      # Check if thread is actually alive, not just if @running is true
      return if @running && @thread&.alive?

      @running = true

      # Start watchdog only when service is explicitly started
      start_watchdog unless @watchdog_thread&.alive?

      @thread = Thread.new do
        Thread.current.name = 'risk-manager'
        last_paper_pnl_update = Time.current

        loop do
          break unless @running

          begin
            monitor_loop(last_paper_pnl_update)
            # update timestamp after paper update occurred inside monitor_loop
            last_paper_pnl_update = Time.current
          rescue StandardError => e
            Rails.logger.error("[RiskManagerService] monitor_loop crashed: #{e.class} - #{e.message}\n#{e.backtrace.first(8).join("\n")}")
          end
          sleep LOOP_INTERVAL
        end
      end
    end

    def stop
      @running = false
      @thread&.kill
      @thread = nil
      @watchdog_thread&.kill
      @watchdog_thread = nil
    end

    def running?
      @running
    end

    # Lightweight risk evaluation helper (unchanged semantics)
    def evaluate_signal_risk(signal_data)
      confidence = signal_data[:confidence] || 0.0
      entry_price = signal_data[:entry_price]
      stop_loss = signal_data[:stop_loss]

      risk_level =
        case confidence
        when 0.8..1.0 then :low
        when 0.6...0.8 then :medium
        else :high
        end

      max_position_size =
        case risk_level
        when :low then 100
        when :medium then 50
        else 25
        end

      recommended_stop_loss = stop_loss || (entry_price * 0.98)

      { risk_level: risk_level, max_position_size: max_position_size, recommended_stop_loss: recommended_stop_loss }
    end
  end
end
