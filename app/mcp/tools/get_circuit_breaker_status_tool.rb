# frozen_string_literal: true

class GetCircuitBreakerStatusTool < ApplicationMCPTool
  tool_name 'get_circuit_breaker_status'
  description "Circuit breaker state (tripped, reason, when) with today's realized daily-loss budget. Read-only."

  def perform
    snapshot = market_snapshot
    risk = snapshot['risk']

    render_json(
      generated_at: snapshot['generated_at'],
      mode: snapshot['mode'],
      circuit_breaker: risk['circuit_breaker'],
      daily_loss: risk['daily_loss']
    )
  end
end
