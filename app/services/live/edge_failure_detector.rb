# frozen_string_literal: true

module Live
  # Edge Failure Detector
  # Detects when trading edge has degraded and pauses entries to prevent death by a thousand cuts
  # This is NOT a loss cap - it's a quality/regime detector
  #
  # Core Philosophy:
  # - Unlimited trades and losses are allowed UNTIL ₹20k profit
  # - BUT edge degradation must be detected and paused
  # - Prevents chop/theta bleed days from causing infinite drawdown
  #
  # Detection Methods:
  # 1. Rolling PnL Window: Last N trades net PnL <= threshold → pause
  # 2. Consecutive SLs: N consecutive stop losses → pause
  # 3. Session-based: Disable entries in dangerous sessions (S3) after consecutive SLs
  #
  # This preserves profit-hunting mode while preventing edge decay days
  class EdgeFailureDetector
    include Singleton

    REDIS_KEY_PREFIX = 'edge_failure'
    TTL_SECONDS = 25.hours.to_i # Slightly longer than 24h

    def initialize(redis: nil)
      @redis = redis || Redis.new(url: ENV.fetch('REDIS_URL', 'redis://127.0.0.1:6379/0'))
    rescue StandardError => e
      Rails.logger.error("[EdgeFailureDetector] Redis init error: #{e.class} - #{e.message}")
      @redis = nil
    end

    # Check if entries should be paused due to edge failure
    # @param index_key [Symbol, String] Index key (optional, for per-index tracking)
    # @return [Hash] { paused: true/false, reason: "...", resume_at: Time }
    def entries_paused?(index_key: nil)
      return { paused: false, reason: nil } unless enabled?

      # Check rolling PnL window breaker
      rolling_check = check_rolling_pnl_window(index_key: index_key)
      return rolling_check if rolling_check[:paused]

      # Check consecutive SL breaker
      consecutive_check = check_consecutive_sls(index_key: index_key)
      return consecutive_check if consecutive_check[:paused]

      # Check session-based pause (especially S3)
      session_check = check_session_based_pause(index_key: index_key)
      return session_check if session_check[:paused]

      { paused: false, reason: nil }
    rescue StandardError => e
      Rails.logger.error("[EdgeFailureDetector] entries_paused? error: #{e.class} - #{e.message}")
      { paused: false, reason: nil } # Fail-safe: allow entries if check fails
    end

    # Record a trade result for edge detection
    # @param index_key [Symbol, String] Index key
    # @param pnl_rupees [Float, BigDecimal] Trade PnL (negative for loss, positive for profit)
    # @param exit_reason [String] Exit reason (e.g., "SL HIT", "TP HIT")
    # @param exit_time [Time] Exit time (defaults to now)
    def record_trade_result(index_key:, pnl_rupees:, exit_reason:, exit_time: nil)
      return false unless @redis

      index_key = normalize_index_key(index_key)
      exit_time ||= Time.current
      pnl_rupees = pnl_rupees.to_f

      # Record trade in rolling window
      record_in_rolling_window(index_key: index_key, pnl: pnl_rupees, exit_time: exit_time)

      # Record if it was a stop loss
      if stop_loss?(exit_reason)
        record_stop_loss(index_key: index_key, exit_time: exit_time)
      else
        # Reset consecutive SL counter on any non-SL exit
        reset_consecutive_sls(index_key: index_key)
      end

      true
    rescue StandardError => e
      Rails.logger.error("[EdgeFailureDetector] record_trade_result error: #{e.class} - #{e.message}")
      false
    end

    # Clear pause state (manual override or after resume time)
    def clear_pause(index_key: nil)
      return false unless @redis

      index_key = normalize_index_key(index_key) if index_key

      if index_key
        # Clear per-index pause
        pause_key = pause_state_key(index_key)
        @redis.del(pause_key)
      else
        # Clear all pauses
        pattern = "#{REDIS_KEY_PREFIX}:pause:*"
        @redis.scan_each(match: pattern) { |key| @redis.del(key) }
      end

      true
    rescue StandardError => e
      Rails.logger.error("[EdgeFailureDetector] clear_pause error: #{e.class} - #{e.message}")
      false
    end

    private

    def enabled?
      config = edge_failure_config
      config[:enabled] == true
    rescue StandardError
      false
    end

    def edge_failure_config
      AlgoConfig.fetch.dig(:risk, :edge_failure_detector) || {}
    rescue StandardError
      {}
    end

    # Check rolling PnL window breaker
    def check_rolling_pnl_window(index_key: nil)
      config = edge_failure_config
      window_size = config[:rolling_window_size] || 5
      threshold_rupees = BigDecimal((config[:rolling_window_threshold_rupees] || -3000).to_s)

      # Get last N trades
      trades = get_rolling_window_trades(index_key: index_key, window_size: window_size)
      return { paused: false, reason: nil } if trades.size < window_size

      # Calculate net PnL of last N trades
      net_pnl = trades.sum { |t| t[:pnl].to_f }
      return { paused: false, reason: nil } if net_pnl > threshold_rupees.to_f

      # Check if already paused
      pause_state = get_pause_state(index_key: index_key, reason: 'rolling_pnl_window')
      return pause_state if pause_state[:paused]

      # Set pause
      pause_duration_minutes = config[:pause_duration_minutes] || 60
      resume_at = Time.current + pause_duration_minutes.minutes
      set_pause_state(
        index_key: index_key,
        reason: 'rolling_pnl_window',
        resume_at: resume_at,
        details: {
          net_pnl: net_pnl.round(2),
          threshold: threshold_rupees.to_f,
          window_size: window_size,
          trades_count: trades.size
        }
      )

      Rails.logger.warn(
        '[EdgeFailureDetector] Entries paused: Rolling PnL window breaker ' \
        "(last #{window_size} trades: ₹#{net_pnl.round(2)}, threshold: ₹#{threshold_rupees}, " \
        "resume at: #{resume_at.strftime('%H:%M IST')})"
      )

      {
        paused: true,
        reason: 'rolling_pnl_window',
        resume_at: resume_at,
        net_pnl: net_pnl.round(2),
        threshold: threshold_rupees.to_f
      }
    end

    # Check consecutive SL breaker
    def check_consecutive_sls(index_key: nil)
      config = edge_failure_config
      max_consecutive_sls = config[:max_consecutive_sls] || 2

      consecutive_count = get_consecutive_sl_count(index_key: index_key)
      return { paused: false, reason: nil } if consecutive_count < max_consecutive_sls

      # Check if already paused
      pause_state = get_pause_state(index_key: index_key, reason: 'consecutive_sls')
      return pause_state if pause_state[:paused]

      # Set pause
      pause_duration_minutes = config[:consecutive_sl_pause_minutes] || 60
      resume_at = Time.current + pause_duration_minutes.minutes
      set_pause_state(
        index_key: index_key,
        reason: 'consecutive_sls',
        resume_at: resume_at,
        details: {
          consecutive_sls: consecutive_count,
          max_allowed: max_consecutive_sls
        }
      )

      Rails.logger.warn(
        '[EdgeFailureDetector] Entries paused: Consecutive SL breaker ' \
        "(#{consecutive_count} consecutive SLs, max allowed: #{max_consecutive_sls}, " \
        "resume at: #{resume_at.strftime('%H:%M IST')})"
      )

      {
        paused: true,
        reason: 'consecutive_sls',
        resume_at: resume_at,
        consecutive_count: consecutive_count
      }
    end

    # Check session-based pause (especially S3 - chop/decay zone)
    def check_session_based_pause(index_key: nil)
      config = edge_failure_config
      return { paused: false, reason: nil } unless config[:session_based_pause] == true

      regime = Live::TimeRegimeService.instance.current_regime

      # In S3 (chop/decay), disable entries after consecutive SLs
      if regime == Live::TimeRegimeService::CHOP_DECAY
        consecutive_count = get_consecutive_sl_count(index_key: index_key)
        max_s3_consecutive_sls = config[:s3_max_consecutive_sls] || 2

        if consecutive_count >= max_s3_consecutive_sls
          # Pause until S4 (close/gamma zone) starts
          s4_start = parse_time(config[:s4_start_time] || '13:45')
          resume_at = s4_start || 2.hours.from_now # Fallback: 2 hours

          pause_state = get_pause_state(index_key: index_key, reason: 'session_s3_pause')
          return pause_state if pause_state[:paused] && pause_state[:resume_at] > Time.current

          set_pause_state(
            index_key: index_key,
            reason: 'session_s3_pause',
            resume_at: resume_at,
            details: {
              regime: regime.to_s,
              consecutive_sls: consecutive_count,
              resume_at_regime: 'close_gamma'
            }
          )

          Rails.logger.warn(
            '[EdgeFailureDetector] Entries paused: S3 session breaker ' \
            "(#{consecutive_count} consecutive SLs in CHOP_DECAY zone, " \
            "resume at S4 start: #{resume_at.strftime('%H:%M IST')})"
          )

          return {
            paused: true,
            reason: 'session_s3_pause',
            resume_at: resume_at,
            regime: regime.to_s
          }
        end
      end

      { paused: false, reason: nil }
    end

    # Record trade in rolling window
    def record_in_rolling_window(index_key:, pnl:, exit_time:)
      key = rolling_window_key(index_key)
      trade_data = {
        pnl: pnl.to_f,
        exit_time: exit_time.to_i
      }.to_json

      # Add to list (FIFO - keep last N trades)
      @redis.lpush(key, trade_data)
      @redis.ltrim(key, 0, (edge_failure_config[:rolling_window_size] || 5) - 1)
      @redis.expire(key, TTL_SECONDS)
    end

    # Get rolling window trades
    def get_rolling_window_trades(index_key:, window_size:)
      return [] unless @redis

      key = rolling_window_key(index_key)
      data = @redis.lrange(key, 0, window_size - 1)
      data.map do |json_str|
        trade = JSON.parse(json_str)
        {
          pnl: trade['pnl'].to_f,
          exit_time: Time.zone.at(trade['exit_time'].to_i)
        }
      end
    rescue StandardError => e
      Rails.logger.error("[EdgeFailureDetector] get_rolling_window_trades error: #{e.class} - #{e.message}")
      []
    end

    # Record stop loss
    def record_stop_loss(index_key:, exit_time:)
      key = consecutive_sl_key(index_key)
      @redis.incr(key)
      @redis.expire(key, TTL_SECONDS)
    end

    # Reset consecutive SL counter
    def reset_consecutive_sls(index_key:)
      key = consecutive_sl_key(index_key)
      @redis.del(key)
    end

    # Get consecutive SL count
    def get_consecutive_sl_count(index_key:)
      return 0 unless @redis

      key = consecutive_sl_key(index_key)
      value = @redis.get(key)
      (value || 0).to_i
    rescue StandardError
      0
    end

    # Get pause state
    def get_pause_state(index_key:, reason:)
      return { paused: false, reason: nil } unless @redis

      key = pause_state_key(index_key, reason)
      data = @redis.get(key)
      return { paused: false, reason: nil } unless data

      pause_data = JSON.parse(data)
      resume_at = Time.zone.at(pause_data['resume_at'].to_i)

      # Check if pause has expired
      if resume_at <= Time.current
        @redis.del(key)
        return { paused: false, reason: nil }
      end

      {
        paused: true,
        reason: pause_data['reason'],
        resume_at: resume_at,
        details: pause_data['details']
      }
    rescue StandardError => e
      Rails.logger.error("[EdgeFailureDetector] get_pause_state error: #{e.class} - #{e.message}")
      { paused: false, reason: nil }
    end

    # Set pause state
    def set_pause_state(index_key:, reason:, resume_at:, details: {})
      return false unless @redis

      key = pause_state_key(index_key, reason)
      pause_data = {
        reason: reason,
        resume_at: resume_at.to_i,
        paused_at: Time.current.to_i,
        details: details
      }.to_json

      @redis.setex(key, TTL_SECONDS, pause_data)
      true
    end

    def stop_loss?(exit_reason)
      return false unless exit_reason

      reason_lower = exit_reason.to_s.downcase
      reason_lower.include?('sl') || reason_lower.include?('stop_loss') || reason_lower.include?('loss')
    end

    def normalize_index_key(index_key)
      return 'GLOBAL' unless index_key

      index_key.to_s.strip.upcase
    end

    def parse_time(time_str)
      return nil unless time_str

      Time.zone.parse(time_str)
    rescue StandardError
      nil
    end

    # Redis keys
    def rolling_window_key(index_key)
      index_key = normalize_index_key(index_key)
      "#{REDIS_KEY_PREFIX}:rolling_window:#{index_key}"
    end

    def consecutive_sl_key(index_key)
      index_key = normalize_index_key(index_key)
      "#{REDIS_KEY_PREFIX}:consecutive_sl:#{index_key}"
    end

    def pause_state_key(index_key, reason = nil)
      index_key = normalize_index_key(index_key)
      key = "#{REDIS_KEY_PREFIX}:pause:#{index_key}"
      key += ":#{reason}" if reason
      key
    end
  end
end
