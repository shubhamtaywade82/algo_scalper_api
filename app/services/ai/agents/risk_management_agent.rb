# frozen_string_literal: true

module Ai
  module Agents
    # Blueprint §8.5 "Risk Management Agent" — read-only risk assessment
    # layered on top of the existing reactive risk system (Risk::CircuitBreaker,
    # DrawdownGuard). It never trips the breaker, adjusts a limit, or force
    # closes anything itself; it only publishes an observational :risk_alert
    # and logs its assessment so a human (or a future, deliberately promoted
    # Level 2 agent) has an early warning signal to act on.
    class RiskManagementAgent < BaseAgent
      CONSECUTIVE_LOSS_ALERT_THRESHOLD = 2
      DAILY_LOSS_ALERT_RUPEES = 3_000

      private

      def perform
        cb_status = Risk::CircuitBreaker.instance.status
        active_positions = PositionTracker.active.count
        exited_today = PositionTracker.exited.where(exited_at: Time.current.beginning_of_day..).order(exited_at: :desc)
        today_pnl = exited_today.sum { |t| t.last_pnl_rupees.to_f }
        consecutive_losses = exited_today.first(5).map { |t| t.last_pnl_rupees.to_f }
                                         .take_while(&:negative?).size

        level = risk_level(cb_status, today_pnl, consecutive_losses)
        alert = level != :normal

        if alert
          publish(:risk_alert, {
                    level: level, today_pnl: today_pnl.round(2), consecutive_losses: consecutive_losses,
                    circuit_breaker_tripped: cb_status[:tripped], at: Time.current
                  })
        end

        {
          decision_type: 'risk_assessment',
          confidence: 1.0,
          published_event: alert ? 'risk_alert' : nil,
          output: {
            risk_level: level,
            circuit_breaker_tripped: cb_status[:tripped],
            active_positions: active_positions,
            today_realized_pnl_rupees: today_pnl.round(2),
            recent_consecutive_losses: consecutive_losses
          }
        }
      end

      def risk_level(cb_status, today_pnl, consecutive_losses)
        return :critical if cb_status[:tripped]
        return :elevated if consecutive_losses >= CONSECUTIVE_LOSS_ALERT_THRESHOLD
        return :elevated if today_pnl.negative? && today_pnl.abs >= DAILY_LOSS_ALERT_RUPEES

        :normal
      end
    end
  end
end
