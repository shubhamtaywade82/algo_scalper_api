# frozen_string_literal: true

require "singleton"
require "bigdecimal"
require "bigdecimal/util"
require "yaml"
require "concurrent/map"

module Orders
  class RiskManager
    include Singleton

    DEFAULT_RULE_KEY = "index_options_buy".freeze
    RULES_PATH = Rails.root.join("config", "risk_rules.yml")

    def initialize
      @rules = {}
      @state = Concurrent::Map.new
      load_rules!
    end

    def load_rules!
      @rules = if RULES_PATH.exist?
                 YAML.load_file(RULES_PATH) || {}
               else
                 {}
               end
      @rules = @rules.deep_stringify_keys
    rescue Psych::SyntaxError => e
      Rails.logger.error("Risk rules YAML parse failed: #{e.message}")
      @rules = {}
    end

    def register_tracker(tracker)
      @state.delete(tracker_key(tracker))
    end

    def deregister_tracker(tracker)
      @state.delete(tracker_key(tracker))
    end

    def evaluate!(tracker:, tick:)
      return unless tracker&.active?

      rule = rule_for(tracker)
      return unless rule

      ltp = safe_decimal(tick[:ltp])
      return if ltp.nil? || ltp <= 0

      state = ensure_state(tracker, rule, ltp)
      return if state[:exit_triggered]

      state[:highest_price] = [state[:highest_price], ltp].compact.max
      maybe_update_trailing_stop(state, tracker, ltp, rule)

      if stop_triggered?(tracker, ltp, state)
        trigger_exit(tracker, ltp, state, :stop_loss)
      elsif target_reached?(tracker, ltp, state)
        trigger_exit(tracker, ltp, state, :take_profit)
      end
    rescue StandardError => e
      Rails.logger.error("RiskManager evaluate failed for #{tracker&.order_no}: #{e.class} - #{e.message}")
    end

    private

    def rule_for(tracker)
      segment = tracker.resolved_exchange_segment
      return unless segment

      key = tracker.strategy_key
      rule = @rules[key] || @rules[DEFAULT_RULE_KEY]
      return unless rule.present?

      allowed_segments = Array(rule["segments"]).map(&:to_s)
      return rule if allowed_segments.empty? || allowed_segments.include?(segment.to_s)

      nil
    end

    def ensure_state(tracker, rule, ltp)
      key = tracker_key(tracker)
      @state.compute_if_absent(key) do
        entry_price = tracker.entry_price ? BigDecimal(tracker.entry_price.to_s) : ltp
        stop_pct = safe_decimal(rule["stop_loss_pct"]) || BigDecimal("0")
        target_pct = safe_decimal(rule["take_profit_pct"]) || BigDecimal("0")
        activation_pct = safe_decimal(rule["trail_activation_pct"]) || target_pct
        breakeven_pct = safe_decimal(rule["breakeven_pct"]) || BigDecimal("0")

        {
          entry_price: entry_price,
          stop_price: entry_price * (BigDecimal("1") - stop_pct),
          target_price: target_pct.zero? ? nil : entry_price * (BigDecimal("1") + target_pct),
          trail_activation_price: entry_price * (BigDecimal("1") + activation_pct),
          breakeven_price: breakeven_pct.zero? ? nil : entry_price * (BigDecimal("1") + breakeven_pct),
          highest_price: entry_price,
          trailing_stop: nil,
          atr: fetch_atr(tracker, rule),
          exit_triggered: false
        }
      end
    end

    def maybe_update_trailing_stop(state, tracker, ltp, rule)
      return unless tracker.buy?

      activation = state[:trail_activation_price]
      return if activation && ltp < activation

      trail_pct = safe_decimal(rule["trail_step_pct"]) || BigDecimal("0")
      atr_multiple = safe_decimal(rule["trail_atr_multiple"]) || BigDecimal("0")

      candidates = []
      candidates << (ltp * (BigDecimal("1") - trail_pct)) unless trail_pct.zero?
      if !atr_multiple.zero? && state[:atr]
        candidates << (ltp - (state[:atr] * atr_multiple))
      end
      return if candidates.empty?

      new_stop = candidates.compact.max
      return unless new_stop

      new_stop = [new_stop, state[:stop_price]].compact.max
      if state[:breakeven_price]
        new_stop = [new_stop, state[:breakeven_price]].max
      end

      state[:trailing_stop] = if state[:trailing_stop]
                                [state[:trailing_stop], new_stop].max
                              else
                                new_stop
                              end
    end

    def stop_triggered?(tracker, ltp, state)
      return false unless tracker.buy?

      thresholds = [state[:stop_price], state[:trailing_stop]].compact
      return false if thresholds.empty?

      ltp <= thresholds.max
    end

    def target_reached?(tracker, ltp, state)
      tracker.buy? && state[:target_price] && ltp >= state[:target_price]
    end

    def trigger_exit(tracker, ltp, state, reason)
      state[:exit_triggered] = true
      Positions::Manager.instance.exit_position(tracker, reason: reason, exit_price: ltp)
    rescue StandardError => e
      state[:exit_triggered] = false
      Rails.logger.error("RiskManager exit failed for #{tracker.order_no}: #{e.class} - #{e.message}")
    end

    def tracker_key(tracker)
      tracker.order_no.to_s
    end

    def safe_decimal(value)
      return if value.nil?

      case value
      when BigDecimal
        value
      when Numeric
        BigDecimal(value.to_s)
      else
        str = value.to_s
        return if str.empty?

        BigDecimal(str)
      end
    rescue ArgumentError
      nil
    end

    def fetch_atr(tracker, rule)
      instrument = tracker.instrument
      return unless instrument

      interval = rule["atr_interval"] || "5"
      days = rule["atr_lookback_days"] || 3
      period = (rule["atr_period"] || 14).to_i

      raw = instrument.intraday_ohlc(interval: interval, days: days)
      return unless raw

      series = CandleSeries.new(symbol: instrument.symbol_name || instrument.security_id, interval: interval)
      series.load_from_raw(raw)
      value = series.atr(period)
      safe_decimal(value)
    rescue StandardError => e
      Rails.logger.warn("ATR fetch failed for #{tracker.order_no}: #{e.class} - #{e.message}")
      nil
    end
  end
end
