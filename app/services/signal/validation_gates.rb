# frozen_string_literal: true

module Signal
  # Runs the comprehensive pre-entry validation checks (IV rank, theta risk,
  # ADX strength, trend confirmation, market timing) plus the trading-context
  # gate. Extracted from Signal::Engine.
  class ValidationGates
    class << self
      def comprehensive_validation(index_cfg, direction, series, supertrend_result, adx, supertrend_only: false, validation_mode: nil)
        mode_config = Signal::ConfigResolver.validation_mode_config(override_mode: validation_mode)

        validation_checks = []

        # 1. IV Rank Check - Avoid extreme volatility (if enabled)
        if mode_config[:require_iv_rank_check]
          iv_rank_result = validate_iv_rank(index_cfg, series, mode_config)
          validation_checks << iv_rank_result
        end

        # 2. Theta Risk Assessment - Avoid high theta decay (if enabled)
        if mode_config[:require_theta_risk_check]
          theta_risk_result = validate_theta_risk(index_cfg, direction, mode_config)
          validation_checks << theta_risk_result
        end

        # 3. Enhanced ADX Confirmation - Ensure strong trend (if enabled)
        # Loss Avoidance: Enforce ADX even in supertrend_only mode if filter is enabled,
        # as analysis shows ADX < 15 has 16.7% win rate across all strategies.
        signals_cfg = AlgoConfig.fetch[:signals] || {}
        enable_adx_filter = signals_cfg.fetch(:enable_adx_filter, true)
        if enable_adx_filter
          adx_result = validate_adx_strength(index_cfg, adx, supertrend_result, mode_config)
          validation_checks << adx_result
        elsif !supertrend_only
          validation_checks << { valid: true, name: 'ADX Strength', message: 'ADX filter disabled' }
        end

        # 4. Trend Confirmation - Multiple signal validation (if enabled); skipped when supertrend_only
        if !supertrend_only && mode_config[:require_trend_confirmation]
          trend_result = validate_trend_confirmation(supertrend_result, series)
          validation_checks << trend_result
        end

        # 5. Market Timing Check - Avoid problematic times (always required)
        timing_result = validate_market_timing
        validation_checks << timing_result

        # Determine overall validation result
        failed_checks = validation_checks.reject { |check| check[:valid] }

        if failed_checks.empty?
          { valid: true, reason: 'All checks passed' }
        else
          failed_reasons = failed_checks.pluck(:name).join(', ')
          failed_messages = failed_checks.map { |check| "#{check[:name]}: #{check[:message]}" }.join('; ')
          { valid: false, reason: "Failed checks: #{failed_reasons} (#{failed_messages})" }
        end
      end

      def validate_iv_rank(_index_cfg, series, mode_config = nil)
        mode_config = Signal::ConfigResolver.validation_mode_config(override_mode: mode_config) if mode_config.nil? || mode_config.is_a?(String) || mode_config.is_a?(Symbol)
        mode_config = Signal::ConfigResolver.validation_mode_config unless mode_config.is_a?(Hash)

        # For now, we'll use a simple volatility check based on recent price movement
        # In a full implementation, you'd calculate actual IV rank from historical IV data

        candles = series.candles
        if candles.blank? || candles.size < 5
          return { valid: false, name: 'IV Rank', message: 'Insufficient data for volatility assessment' }
        end

        # Calculate recent volatility as a proxy for IV rank
        # series.candles is an array of Candle objects
        recent_candles = candles.last(5)
        return { valid: false, name: 'IV Rank', message: 'Insufficient recent candles' } if recent_candles.size < 2

        price_changes = recent_candles.each_cons(2).map { |c1, c2| (c2.close - c1.close).abs / c1.close }
        avg_volatility = price_changes.sum / price_changes.size

        # Normalize volatility (this is a simplified approach)
        iv_rank_proxy = [(avg_volatility * 1000), 1.0].min # Cap at 1.0

        max_threshold = mode_config[:iv_rank_max] || 0.8
        min_threshold = mode_config[:iv_rank_min] || 0.1

        if iv_rank_proxy > max_threshold
          { valid: false, name: 'IV Rank', message: "Extreme volatility detected (#{(iv_rank_proxy * 100).round(1)}% > #{(max_threshold * 100).round(1)}%)" }
        elsif iv_rank_proxy < min_threshold
          { valid: false, name: 'IV Rank', message: "Very low volatility (#{(iv_rank_proxy * 100).round(1)}% < #{(min_threshold * 100).round(1)}%)" }
        else
          { valid: true, name: 'IV Rank', message: "Volatility within acceptable range (#{(iv_rank_proxy * 100).round(1)}%)" }
        end
      end

      # Validate theta risk - avoid high theta decay situations
      def validate_theta_risk(_index_cfg, _direction, mode_config = nil)
        mode_config = Signal::ConfigResolver.validation_mode_config(override_mode: mode_config) if mode_config.nil? || mode_config.is_a?(String) || mode_config.is_a?(Symbol)
        mode_config = Signal::ConfigResolver.validation_mode_config unless mode_config.is_a?(Hash)

        current_time = Time.zone.now
        hour = current_time.hour
        minute = current_time.min

        cutoff_hour = mode_config[:theta_risk_cutoff_hour] || 14
        cutoff_minute = mode_config[:theta_risk_cutoff_minute] || 30

        # High theta risk periods (configurable cutoff time)
        if hour > cutoff_hour || (hour == cutoff_hour && minute >= cutoff_minute)
          { valid: false, name: 'Theta Risk', message: "High theta decay risk - too close to market close (after #{cutoff_hour}:#{cutoff_minute.to_s.rjust(2, '0')})" }
        elsif hour >= 14 # After 2:00 PM
          { valid: true, name: 'Theta Risk', message: 'Moderate theta risk - afternoon trading' }
        else
          { valid: true, name: 'Theta Risk', message: 'Low theta risk - early/midday trading' }
        end
      end

      # Enhanced ADX validation with trend strength assessment
      def validate_adx_strength(index_cfg, adx, _supertrend_result, mode_config = nil)
        mode_config ||= Signal::ConfigResolver.validation_mode_config

        adx_value = adx[:value].to_f
        # 1. Check per-index override
        # 2. Check mode config (e.g., balanced/strict)
        # 3. Check global signals default
        min_strength =
          index_cfg.dig(:adx_thresholds, :primary_min_strength) ||
          mode_config[:adx_min_strength] ||
          AlgoConfig.fetch.dig(:signals, :adx, :min_strength).to_f

        if adx_value < min_strength
          { valid: false, name: 'ADX Strength', message: "Weak trend strength (#{adx_value.round(1)} < #{min_strength})" }
        elsif adx_value >= 40
          { valid: true, name: 'ADX Strength', message: "Very strong trend (#{adx_value.round(1)})" }
        elsif adx_value >= 25
          { valid: true, name: 'ADX Strength', message: "Strong trend (#{adx_value.round(1)})" }
        else
          { valid: true, name: 'ADX Strength', message: "Moderate trend (#{adx_value.round(1)})" }
        end
      end

      # Validate trend confirmation with multiple signals
      def validate_trend_confirmation(supertrend_result, series)
        trend = supertrend_result[:trend]

        return { valid: false, name: 'Trend Confirmation', message: 'No trend signal from Supertrend' } if trend.nil?

        # Additional confirmation: check if recent price action supports the trend
        candles = series.candles
        if candles.blank? || candles.size < 3
          return { valid: false, name: 'Trend Confirmation', message: 'Insufficient data for trend confirmation' }
        end

        recent_candles = candles.last(3)

        # Check if recent closes are moving in trend direction
        case trend
        when :bullish
          if recent_candles.last.close > recent_candles.first.close
            { valid: true, name: 'Trend Confirmation', message: 'Bullish trend confirmed by price action' }
          else
            { valid: false, name: 'Trend Confirmation', message: 'Bullish signal not confirmed by recent price action' }
          end
        when :bearish
          if recent_candles.last.close < recent_candles.first.close
            { valid: true, name: 'Trend Confirmation', message: 'Bearish trend confirmed by price action' }
          else
            { valid: false, name: 'Trend Confirmation', message: 'Bearish signal not confirmed by recent price action' }
          end
        else
          { valid: false, name: 'Trend Confirmation', message: 'Unknown trend direction' }
        end
      end

      # Validate market timing - avoid problematic trading times
      def validate_market_timing
        unless Market::Calendar.trading_day_today?
          return { valid: false, name: 'Market Timing', message: 'Not a trading day (weekend/holiday)' }
        end

        current_ist = TradingSession::Service.current_ist_time
        hour = current_ist.hour
        minute = current_ist.min

        # Market hours: 9:15 AM to 3:30 PM IST
        market_open = hour > 9 || (hour == 9 && minute >= 15)
        market_close = hour > 15 || (hour == 15 && minute >= 30)

        if !market_open
          { valid: false, name: 'Market Timing', message: 'Market not yet open' }
        elsif market_close
          { valid: false, name: 'Market Timing', message: 'Market closed' }
        else
          # Check for session blackouts (Loss Avoidance)
          restrictions = AlgoConfig.fetch[:trading_time_restrictions]
          if restrictions&.[](:enabled) && restrictions[:avoid_periods].present?
            current_hm = current_ist.strftime('%H:%M')
            restrictions[:avoid_periods].each do |period|
              start_time, end_time = period.split('-')
              if current_hm >= start_time && current_hm < end_time
                return { valid: false, name: 'Market Timing', message: "Loss Avoidance: Blocked during non-profitable session (#{period})" }
              end
            end
          end

          if hour == 9 && minute < 30
            { valid: true, name: 'Market Timing', message: 'Early market - high volatility period' }
          elsif hour >= 14 && minute >= 30
            { valid: true, name: 'Market Timing', message: 'Late market - theta decay risk' }
          else
            { valid: true, name: 'Market Timing', message: 'Normal trading hours' }
          end
        end
      end

      def trading_context_blocked?(index_cfg, primary_series, primary_analysis, regime_result, regime_state, exit_testing_mode, signals_cfg)
        return false unless signals_cfg.fetch(:enable_trading_context_gate, true)
        return false if !regime_state || exit_testing_mode

        indicators = {
          adx_value: primary_analysis[:adx_value],
          regime_confidence: regime_result&.[](:confidence)
        }
        context = Context::Builder.call(
          market: primary_series,
          indicators: indicators,
          regime_state: regime_state,
          index_key: index_cfg[:key]
        )
        unless context.tradable?
          Rails.logger.info(
            "[Signal] TradingContext BLOCKED #{index_cfg[:key]}: day_type=#{context.day_type} session=#{context.session} " \
            "regime=#{context.regime} score=#{context.score} stability=#{context.stability} (not tradable)"
          )
          return true
        end
        Rails.logger.debug do
          "[Signal] TradingContext PASSED #{index_cfg[:key]}: #{context.day_type}/#{context.session}/#{context.regime} " \
            "score=#{context.score} stability=#{context.stability}"
        end
        false
      end
    end
  end
end
