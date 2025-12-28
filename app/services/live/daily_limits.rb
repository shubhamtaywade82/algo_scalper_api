# frozen_string_literal: true

module Live
  # DailyLimits service for NEMESIS V3
  # Enforces per-index and global daily loss limits and trade frequency limits
  # Uses Redis for persistent counters with auto-lock behavior
  # rubocop:disable Metrics/ClassLength, Naming/PredicateMethod, Naming/AccessorMethodName
  class DailyLimits
    REDIS_KEY_PREFIX = 'daily_limits'
    TTL_SECONDS = 25.hours.to_i # Slightly longer than 24h to handle timezone edge cases

    def initialize(redis: nil)
      @redis = redis || Redis.new(url: ENV.fetch('REDIS_URL', 'redis://127.0.0.1:6379/0'))
    rescue StandardError => e
      Rails.logger.error("[DailyLimits] Redis init error: #{e.class} - #{e.message}")
      @redis = nil
    end

    # Check if trading is allowed for the given index
    # @param index_key [Symbol, String] Index key (e.g., :NIFTY, :BANKNIFTY)
    # @return [Hash] { allowed: true/false, reason: "..." }
    # rubocop:disable Metrics/AbcSize
    def can_trade?(index_key:)
      return { allowed: false, reason: 'redis_unavailable' } unless @redis

      index_key = normalize_index_key(index_key)
      risk_config = load_risk_config

      # Check daily profit target first (always enforced)
      global_daily_profit = get_global_daily_profit
      max_daily_profit = risk_config[:max_daily_profit] || risk_config[:daily_profit_target]
      if max_daily_profit&.to_f&.positive? && global_daily_profit >= max_daily_profit.to_f
        return {
          allowed: false,
          reason: 'daily_profit_target_reached',
          global_daily_profit: global_daily_profit,
          max_daily_profit: max_daily_profit.to_f
        }
      end

      # Daily loss limits ONLY enforced when daily profit >= ₹20k (protect profits)
      # If profit < ₹20k, allow trading even if loss limits exceeded
      profit_threshold = max_daily_profit&.to_f || 20_000.0
      if global_daily_profit >= profit_threshold
        # Check daily loss limit (per-index) - only when profit >= threshold
        daily_loss = get_daily_loss(index_key)
        max_daily_loss = risk_config[:max_daily_loss_pct] || risk_config[:daily_loss_limit_pct]
        # Convert percentage to absolute amount if needed
        # For now, assume max_daily_loss is in rupees (can be enhanced later)
        if max_daily_loss && (daily_loss >= max_daily_loss.to_f)
          return {
            allowed: false,
            reason: 'daily_loss_limit_exceeded',
            daily_loss: daily_loss,
            max_daily_loss: max_daily_loss.to_f,
            index_key: index_key,
            note: 'Loss limit enforced because daily profit >= ₹20k'
          }
        end

        # Check global daily loss limit - only when profit >= threshold
        global_daily_loss = get_global_daily_loss
        max_global_loss = risk_config[:max_global_daily_loss_pct] || risk_config[:global_daily_loss_limit_pct]
        if max_global_loss && global_daily_loss >= max_global_loss.to_f
          return {
            allowed: false,
            reason: 'global_daily_loss_limit_exceeded',
            global_daily_loss: global_daily_loss,
            max_global_loss: max_global_loss.to_f,
            note: 'Loss limit enforced because daily profit >= ₹20k'
          }
        end
      end

      # Trade frequency limits are NOT enforced (no cap on trade count)
      # Trade counts are still tracked for monitoring/analytics but don't block entries

      { allowed: true, reason: nil }
    rescue StandardError => e
      Rails.logger.error("[DailyLimits] can_trade? error: #{e.class} - #{e.message}")
      { allowed: false, reason: "error: #{e.message}" }
    end
    # rubocop:enable Metrics/AbcSize

    # Record a loss for the given index
    # @param index_key [Symbol, String] Index key
    # @param amount [Float, BigDecimal] Loss amount in rupees (positive value)
    # @return [Boolean] True if recorded successfully
    def record_loss(index_key:, amount:)
      return false unless @redis && amount&.positive?

      index_key = normalize_index_key(index_key)
      amount = amount.to_f

      # Increment per-index loss counter
      loss_key = daily_loss_key(index_key)
      @redis.incrbyfloat(loss_key, amount)
      @redis.expire(loss_key, TTL_SECONDS)

      # Increment global loss counter
      global_loss_key = global_daily_loss_key
      @redis.incrbyfloat(global_loss_key, amount)
      @redis.expire(global_loss_key, TTL_SECONDS)

      Rails.logger.info(
        "[DailyLimits] Recorded loss for #{index_key}: ₹#{amount.round(2)} " \
        "(daily: ₹#{get_daily_loss(index_key).round(2)}, global: ₹#{get_global_daily_loss.round(2)})"
      )
      true
    rescue StandardError => e
      Rails.logger.error("[DailyLimits] record_loss error: #{e.class} - #{e.message}")
      false
    end

    # Record a profit for the given index
    # @param index_key [Symbol, String] Index key
    # @param amount [Float, BigDecimal] Profit amount in rupees (positive value)
    # @return [Boolean] True if recorded successfully
    def record_profit(index_key:, amount:)
      return false unless @redis && amount&.positive?

      index_key = normalize_index_key(index_key)
      amount = amount.to_f

      # Increment per-index profit counter
      profit_key = daily_profit_key(index_key)
      @redis.incrbyfloat(profit_key, amount)
      @redis.expire(profit_key, TTL_SECONDS)

      # Increment global profit counter
      global_profit_key = global_daily_profit_key
      @redis.incrbyfloat(global_profit_key, amount)
      @redis.expire(global_profit_key, TTL_SECONDS)

      global_profit = get_global_daily_profit
      Rails.logger.info(
        "[DailyLimits] Recorded profit for #{index_key}: ₹#{amount.round(2)} " \
        "(daily: ₹#{get_daily_profit(index_key).round(2)}, global: ₹#{global_profit.round(2)})"
      )

      # Check if daily profit target reached and log warning
      risk_config = load_risk_config
      max_daily_profit = risk_config[:max_daily_profit] || risk_config[:daily_profit_target]
      if max_daily_profit && global_profit >= max_daily_profit.to_f
        Rails.logger.warn(
          '[DailyLimits] ⚠️ DAILY PROFIT TARGET REACHED: ' \
          "₹#{global_profit.round(2)} >= ₹#{max_daily_profit.to_f} - Trading will be stopped for the day"
        )
      end

      true
    rescue StandardError => e
      Rails.logger.error("[DailyLimits] record_profit error: #{e.class} - #{e.message}")
      false
    end

    # Record a trade for the given index
    # @param index_key [Symbol, String] Index key
    # @return [Boolean] True if recorded successfully
    def record_trade(index_key:)
      return false unless @redis

      index_key = normalize_index_key(index_key)

      # Increment per-index trade counter
      trades_key = daily_trades_key(index_key)
      @redis.incr(trades_key)
      @redis.expire(trades_key, TTL_SECONDS)

      # Increment global trade counter
      global_trades_key = global_daily_trades_key
      @redis.incr(global_trades_key)
      @redis.expire(global_trades_key, TTL_SECONDS)

      Rails.logger.debug do
        "[DailyLimits] Recorded trade for #{index_key} " \
          "(daily: #{get_daily_trades(index_key)}, global: #{get_global_daily_trades})"
      end
      true
    rescue StandardError => e
      Rails.logger.error("[DailyLimits] record_trade error: #{e.class} - #{e.message}")
      false
    end

    # Reset all daily counters (called at start of trading day)
    # @return [Boolean] True if reset successfully
    def reset_daily_counters
      return false unless @redis

      today = Time.zone.today
      pattern = "#{REDIS_KEY_PREFIX}:*:#{today}"

      deleted_count = 0
      @redis.scan_each(match: pattern) do |key|
        @redis.del(key)
        deleted_count += 1
      end

      Rails.logger.info("[DailyLimits] Reset daily counters: deleted #{deleted_count} keys for #{today}")
      true
    rescue StandardError => e
      Rails.logger.error("[DailyLimits] reset_daily_counters error: #{e.class} - #{e.message}")
      false
    end

    # Get daily loss for index
    # @param index_key [Symbol, String] Index key
    # @return [Float] Daily loss amount
    def get_daily_loss(index_key)
      return 0.0 unless @redis

      key = daily_loss_key(normalize_index_key(index_key))
      value = @redis.get(key)
      (value || 0).to_f
    rescue StandardError => e
      Rails.logger.error("[DailyLimits] get_daily_loss error: #{e.class} - #{e.message}")
      0.0
    end

    # Get global daily loss
    # @return [Float] Global daily loss amount
    def get_global_daily_loss
      return 0.0 unless @redis

      key = global_daily_loss_key
      value = @redis.get(key)
      (value || 0).to_f
    rescue StandardError => e
      Rails.logger.error("[DailyLimits] get_global_daily_loss error: #{e.class} - #{e.message}")
      0.0
    end

    # Get daily trade count for index
    # @param index_key [Symbol, String] Index key
    # @return [Integer] Daily trade count
    def get_daily_trades(index_key)
      return 0 unless @redis

      key = daily_trades_key(normalize_index_key(index_key))
      value = @redis.get(key)
      (value || 0).to_i
    rescue StandardError => e
      Rails.logger.error("[DailyLimits] get_daily_trades error: #{e.class} - #{e.message}")
      0
    end

    # Get global daily trade count
    # @return [Integer] Global daily trade count
    def get_global_daily_trades
      return 0 unless @redis

      key = global_daily_trades_key
      value = @redis.get(key)
      (value || 0).to_i
    rescue StandardError => e
      Rails.logger.error("[DailyLimits] get_global_daily_trades error: #{e.class} - #{e.message}")
      0
    end

    # Get daily profit for index
    # @param index_key [Symbol, String] Index key
    # @return [Float] Daily profit amount
    def get_daily_profit(index_key)
      return 0.0 unless @redis

      key = daily_profit_key(normalize_index_key(index_key))
      value = @redis.get(key)
      (value || 0).to_f
    rescue StandardError => e
      Rails.logger.error("[DailyLimits] get_daily_profit error: #{e.class} - #{e.message}")
      0.0
    end

    # Get global daily profit
    # @return [Float] Global daily profit amount
    def get_global_daily_profit
      return 0.0 unless @redis

      key = global_daily_profit_key
      value = @redis.get(key)
      (value || 0).to_f
    rescue StandardError => e
      Rails.logger.error("[DailyLimits] get_global_daily_profit error: #{e.class} - #{e.message}")
      0.0
    end

    private

    # Normalize index key to string
    def normalize_index_key(index_key)
      index_key.to_s.strip.upcase
    end

    # Load risk configuration from AlgoConfig
    def load_risk_config
      AlgoConfig.fetch[:risk] || {}
    rescue StandardError => e
      Rails.logger.error("[DailyLimits] Failed to load risk config: #{e.class} - #{e.message}")
      {}
    end

    # Get max trades per day for specific index from config
    def get_index_max_trades(index_key)
      index_key = normalize_index_key(index_key)
      indices = AlgoConfig.fetch[:indices] || []
      index_cfg = indices.find { |idx| idx[:key]&.to_s&.upcase == index_key }
      index_cfg&.dig(:trade_limits, :max_trades_per_day) ||
        index_cfg&.dig('trade_limits', 'max_trades_per_day')
    rescue StandardError => e
      Rails.logger.error("[DailyLimits] Failed to get index max trades: #{e.class} - #{e.message}")
      nil
    end

    # Get global max trades per day from config
    def get_global_max_trades
      trade_limits = AlgoConfig.fetch[:trade_limits] || {}
      trade_limits[:global_max_trades_per_day] || trade_limits['global_max_trades_per_day']
    rescue StandardError => e
      Rails.logger.error("[DailyLimits] Failed to get global max trades: #{e.class} - #{e.message}")
      nil
    end

    # Redis key for daily loss (per-index)
    def daily_loss_key(index_key)
      "#{REDIS_KEY_PREFIX}:loss:#{Time.zone.today}:#{index_key}"
    end

    # Redis key for global daily loss
    def global_daily_loss_key
      "#{REDIS_KEY_PREFIX}:loss:#{Time.zone.today}:global"
    end

    # Redis key for daily trades (per-index)
    def daily_trades_key(index_key)
      "#{REDIS_KEY_PREFIX}:trades:#{Time.zone.today}:#{index_key}"
    end

    # Redis key for global daily trades
    def global_daily_trades_key
      "#{REDIS_KEY_PREFIX}:trades:#{Time.zone.today}:global"
    end

    # Redis key for daily profit (per-index)
    def daily_profit_key(index_key)
      "#{REDIS_KEY_PREFIX}:profit:#{Time.zone.today}:#{index_key}"
    end

    # Redis key for global daily profit
    def global_daily_profit_key
      "#{REDIS_KEY_PREFIX}:profit:#{Time.zone.today}:global"
    end
  end
  # rubocop:enable Metrics/ClassLength, Naming/PredicateMethod, Naming/AccessorMethodName
end
