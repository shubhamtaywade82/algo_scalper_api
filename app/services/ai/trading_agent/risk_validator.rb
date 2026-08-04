# frozen_string_literal: true

module Ai
  module TradingAgent
    # Deterministic pre-trade risk gate.
    # Validates trade parameters without LLM — pure rule-based logic.
    class RiskValidator
      MAX_RISK_PERCENT = 2.0
      MIN_RR_RATIO = 1.5
      MAX_DATA_AGE_SECONDS = 300 # 5 minutes

      Result = Struct.new(:approved, :action, :risk_checks)

      class << self
        # Validates a trade signal against risk rules.
        # @param signal [Hash] with :action, :entry_price, :stop_loss, :take_profit, :risk_percent
        # @param equity [Numeric] current account equity
        # @param data_timestamp [Time] when market data was fetched
        # @return [Result]
        def validate(signal, equity:, data_timestamp: nil)
          checks = {}

          action = signal[:action]&.upcase
          entry = signal[:entry_price]&.to_f
          sl = signal[:stop_loss]&.to_f
          tp = signal[:take_profit]&.to_f
          risk_pct = signal[:risk_percent]&.to_f

          # Stop direction
          checks[:stop_direction] = valid_stop_direction?(action, entry, sl)

          # R:R ratio
          rr = calculate_rr(entry, sl, tp)
          checks[:rr_ratio] = rr.round(2)
          checks[:rr_approved] = rr >= MIN_RR_RATIO

          # Risk percent
          checks[:risk_percent] = risk_pct&.round(2)
          checks[:risk_approved] = risk_pct && risk_pct <= MAX_RISK_PERCENT

          # Data freshness
          if data_timestamp
            age = Time.current - data_timestamp
            checks[:data_age_seconds] = age.round(0)
            checks[:data_fresh] = age <= MAX_DATA_AGE_SECONDS
          else
            checks[:data_fresh] = true # Unknown age, don't block
          end

          # Equity
          checks[:equity] = equity&.to_f&.round(2)

          approved = checks.values_at(:stop_direction, :rr_approved, :risk_approved, :data_fresh).all?

          Result.new(
            approved: approved,
            action: approved ? action : 'HOLD',
            risk_checks: checks
          )
        end

        private

        def valid_stop_direction?(action, entry, sl)
          return false unless entry && sl

          case action
          when 'BUY' then sl < entry
          when 'SELL' then sl > entry
          else false
          end
        end

        def calculate_rr(entry, sl, tp)
          return 0 unless entry && sl && tp

          risk = (entry - sl).abs
          reward = (tp - entry).abs
          return 0 if risk.zero?

          reward / risk
        end
      end
    end
  end
end
