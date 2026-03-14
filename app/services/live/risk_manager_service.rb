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
      @algo_config = begin
        AlgoConfig.fetch
      rescue StandardError
        {}
      end
      @paper_mode = @algo_config.dig(:paper_trading, :enabled) == true
      @orders_gateway = Orders.config ? Orders.config.gateway : Orders::GatewayFactory.build(paper_mode: @paper_mode)
      @active_cache = begin
        Positions::ActiveCache.instance
      rescue StandardError => e
        Rails.logger.error("[RiskManagerService] failed to initialize active_cache: #{e.class} - #{e.message}")
        nil
      end
      @mutex = Mutex.new
      @running = false
      @thread = nil
      @market_closed_checked = false # Track if we've already checked after market closed
      @watchdog_thread = nil # Initialize as nil, start watchdog only when service starts
      @redis_pnl_cache = {}
      @cycle_tracker_map = nil
    end

    # Start monitoring loop (non-blocking)
    def start
      # Check if thread is actually alive, not just if @running is true
      return if @running && @thread&.alive?

      @running = true

      # Start watchdog only when service is explicitly started
      start_watchdog unless @watchdog_thread&.alive?

      # Subscribe to high-frequency LTP/PnL events for sub-second risk evaluation
      @event_subscription = Core::EventBus.instance.subscribe(:ltp) do |event|
        handle_pnl_event(event)
      end

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
            @running = false # Stop running on crash to allow watchdog to restart or for tests to verify
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

      if @event_subscription
        Core::EventBus.instance.unsubscribe(@event_subscription)
        @event_subscription = nil
      end
    end

    delegate :sleep, to: :Kernel

    private

    # High-frequency risk evaluation (Event-driven)
    # Reacts immediately to price changes without waiting for LOOP_INTERVAL
    def handle_pnl_event(event)
      return unless @running

      tracker_id = event[:tracker_id]
      return unless tracker_id

      @last_realtime_tick_at = Time.current

      # Use ActiveCache to avoid DB load in the high-frequency path
      tracker = PositionTracker.find_by(id: tracker_id)
      return unless tracker&.active?

      # Evaluate immediate exits (Hard SL, TP, Trailing)
      # We use UnifiedExitChecker for sub-second logic
      exit_decision = Live::UnifiedExitChecker.check_exit_conditions(tracker)

      if exit_decision && exit_decision[:exit]
        reason = "#{exit_decision[:reason]} (Sub-second Trigger)"
        Rails.logger.info("[RiskManager] ⚡ HIGH-FREQUENCY EXIT for #{tracker.order_no}: #{reason}")

        # Execute exit immediately
        engine = @exit_engine || self
        dispatch_exit(engine, tracker, reason)
        tracker.reload
        return unless tracker.active?
      end

      return unless realtime_tick_first_enabled?
      return unless should_run_realtime_enforcement?(tracker_id)

      run_enforcement_for_tracker(tracker, @exit_engine || self)
    rescue StandardError => e
      Rails.logger.error("[RiskManager] Event-driven evaluation failed for tracker=#{tracker_id}: #{e.message}")
    end

    def should_run_realtime_enforcement?(tracker_id)
      gap = realtime_min_enforcement_gap_seconds
      return true if gap <= 0

      @realtime_eval_mutex ||= Mutex.new
      @last_realtime_eval_at ||= {}
      now = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      @realtime_eval_mutex.synchronize do
        last = @last_realtime_eval_at[tracker_id]
        if last.nil? || (now - last) >= gap
          @last_realtime_eval_at[tracker_id] = now
          true
        else
          false
        end
      end
    end

    def running?
      @running
    end

    def active_cache
      @active_cache ||= Positions::ActiveCache.instance
    rescue StandardError => e
      Rails.logger.error("[RiskManagerService] active_cache unavailable: #{e.class} - #{e.message}")
      nil
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
