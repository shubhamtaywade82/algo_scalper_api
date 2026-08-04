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
  # RiskManagerService for NEMESIS V3
  # 5-layer risk enforcement system:
  # 1. Hard Stops (SL/TP)
  # 2. Dynamic Trailing (Tiered/Direct)
  # 3. Market Structure (BOS invalidation)
  # 4. Premium Momentum (Option decay/stagnation)
  # 5. Global/Time Limits (IV collapse, Stall detection, Daily limits)
  class RiskManagerService
    include Runner
    include ExitEnforcement
    include ExitExecution
    include PnlCache
    include Config

    def initialize(exit_engine: nil)
      @exit_engine = exit_engine
      @active_cache = Positions::ActiveCache.instance
      @algo_config = begin
        AlgoConfig.fetch
      rescue StandardError
        {}
      end
      @running = false
      @thread = nil
      @market_closed_checked = false # Track if we've already checked after market closed
      @watchdog_thread = nil # Initialize as nil, start watchdog only when service starts
      @active_enforcements = Concurrent::Map.new
      @last_realtime_eval_at = Concurrent::Map.new
      @redis_pnl_cache = Concurrent::Map.new
      @cycle_tracker_map = nil
    end

    def start
      return if @running

      @running = true
      start_watchdog
      
      # Subscribe to PnL updates from EventBus for high-frequency evaluation
      @event_subscription = Core::EventBus.instance.subscribe(Core::EventBus::EVENTS[:pnl_update]) do |event|
        handle_pnl_event(event)
      end
      
      Rails.logger.info '[RiskManager] Service started'
    end

    def stop
      @running = false
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

      # Concurrency lock: don't process if this tracker is already being analyzed
      # in the main monitor_loop or another event thread.
      return if @active_enforcements.put_if_absent(tracker_id, true)

      begin
        @last_realtime_tick_at = Time.current

        # Use ActivePositionsCache to avoid DB load in the high-frequency path
        tracker = Positions::ActivePositionsCache.instance.active_trackers.find { |t| t.id == tracker_id }
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
          return unless tracker.active?
        end

        # Portfolio-level profit lock evaluation
        begin
          Portfolio::PnlTracker.update_unrealized(
            tracker_id: tracker_id,
            pnl: event[:pnl].to_f
          )
          Portfolio::ProfitLockEngine.evaluate!
        rescue StandardError => e
          Rails.logger.error("[RiskManager] Portfolio::ProfitLockEngine error: #{e.class} - #{e.message}")
        end

        return unless realtime_tick_first_enabled?
        return unless should_run_realtime_enforcement?(tracker_id)

        # We need position_data for the rules
        position_data = Positions::ActiveCache.instance.get_by_tracker_id(tracker_id)
        return unless position_data

        run_enforcement_for_tracker(tracker, @exit_engine || self, position_data: position_data)
      ensure
        @active_enforcements.delete(tracker_id)
      end
    rescue StandardError => e
      Rails.logger.error("[RiskManager] Event-driven evaluation failed for tracker=#{tracker_id}: #{e.class} - #{e.message}")
    end

    def should_run_realtime_enforcement?(tracker_id)
      gap = realtime_min_enforcement_gap_seconds
      return true if gap <= 0

      now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      last = @last_realtime_eval_at[tracker_id]

      if last.nil? || (now - last) >= gap
        @last_realtime_eval_at[tracker_id] = now
        true
      else
        false
      end
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

    private

    # High-frequency risk evaluation (Event-driven)
    # Reacts immediately to price changes without waiting for LOOP_INTERVAL
    def handle_pnl_event(event)
      return unless @running
      
      tracker_id = event[:tracker_id]
      return unless tracker_id

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
      end
    rescue StandardError => e
      Rails.logger.error("[RiskManager] Event-driven evaluation failed for tracker=#{tracker_id}: #{e.message}")
    end
  end
end
