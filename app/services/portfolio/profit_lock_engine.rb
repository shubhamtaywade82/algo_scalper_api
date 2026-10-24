# frozen_string_literal: true

module Portfolio
  # Core portfolio-level profit lock governor.
  #
  # Called on every :ltp EventBus event (via RiskManagerService#handle_pnl_event).
  # Determines the current arm level based on net PnL, ratchets the monotonic floor,
  # and triggers DrawdownGuard when a breach is detected.
  #
  # Levels are configurable in algo.yml under profit_lock.levels.
  # Default: ₹20k → 60% floor, ₹35k → 70% floor, ₹50k → 73% floor
  class ProfitLockEngine
    # Fallback levels used when algo.yml profit_lock.levels is absent or malformed.
    DEFAULT_LEVELS = [
      { trigger: 20_000, lock_ratio: 0.60 },
      { trigger: 35_000, lock_ratio: 0.70 },
      { trigger: 50_000, lock_ratio: 0.73 }
    ].freeze

    class << self
      # Main evaluation entry point. Stateless — reads from PnlTracker, writes back via update_lock.
      # Safe to call on every tick — debounce is handled by the EventBus caller.
      #
      # @return [Boolean] true if a floor breach was detected and DrawdownGuard fired
      def evaluate!
        return false unless enabled?
        return false if DrawdownGuard.triggered? # already fired today, no-op

        net   = PnlTracker.net_pnl
        peak  = PnlTracker.peak_pnl
        level = PnlTracker.current_level

        # Determine which milestone level we're now at
        new_level = determine_level(net)

        # Level is monotonic — never downgrade even if net PnL drops
        effective_level = [new_level, level].max
        return false if effective_level.zero?

        # Ratchet peak upward only
        new_peak   = [net, peak].max
        lock_ratio = levels[effective_level - 1][:lock_ratio]
        new_floor  = new_peak * lock_ratio

        # Write (monotonic) updates back to Redis via PnlTracker
        PnlTracker.update_lock(
          new_peak: new_peak,
          new_floor: new_floor,
          new_level: effective_level
        )

        # Check for floor breach (use the stored floor for monotonic comparison)
        current_floor = PnlTracker.locked_floor
        if current_floor.positive? && net <= current_floor
          Rails.logger.warn(
            "[Portfolio::ProfitLockEngine] 🚨 FLOOR BREACH! " \
            "net=₹#{net.round(2)} ≤ floor=₹#{current_floor.round(2)} " \
            "(Level #{effective_level})"
          )
          DrawdownGuard.trigger_global_exit!(
            net_pnl: net,
            floor: current_floor,
            level: effective_level
          )
          return true
        end

        false
      rescue StandardError => e
        Rails.logger.error("[Portfolio::ProfitLockEngine] evaluate! error: #{e.class} - #{e.message}")
        false
      end

      # Returns the highest level milestone currently exceeded by pnl.
      # 0 = below all thresholds, 1 = ≥₹20k, 2 = ≥₹35k, 3 = ≥₹50k, etc.
      #
      # @param pnl [Float]
      # @return [Integer]
      def determine_level(pnl)
        levels.count { |l| pnl >= l[:trigger] }
      end

      # Sorted profit lock levels from config (or defaults).
      # Memoized per process — call reset_levels_cache! after config reload.
      # @return [Array<Hash>]
      def levels
        @levels ||= begin
          cfg = AlgoConfig.fetch.dig(:profit_lock, :levels)
          if cfg.is_a?(Array) && cfg.any?
            cfg.map { |l| { trigger: l[:trigger].to_f, lock_ratio: l[:lock_ratio].to_f } }
               .sort_by { |l| l[:trigger] }
          else
            DEFAULT_LEVELS
          end
        rescue StandardError
          DEFAULT_LEVELS
        end
      end

      # Refresh the levels cache (call after AlgoConfig.reload)
      def reset_levels_cache!
        @levels = nil
      end

      private

      def enabled?
        AlgoConfig.fetch.dig(:profit_lock, :enabled) != false
      rescue StandardError
        true
      end
    end
  end
end
