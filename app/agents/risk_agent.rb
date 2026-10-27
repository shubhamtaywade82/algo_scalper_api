# frozen_string_literal: true

# Assesses risk for a proposed strategy against active positions, margins,
# account funds, and portfolio risk limits.
class RiskAgent < ApplicationAgent
  tools GetAccountStatusTool

  inputs :strategy_details

  instructions <<~PROMPT
    You are the Risk Agent for an options trading bot.
    Your job is to assess the risk of a proposed trading strategy against the current account status.
    Use the `GetAccountStatusTool` tool to retrieve the current available capital, daily stats, and active positions.
    Rules:
    1. If the proposed action is `NO_TRADE`, approve it (verdict: APPROVED, notes: "No trade proposed").
    2. Check if we have active positions. If we already have 3 or more active positions, reject the trade (verdict: REJECTED, notes: "Max active positions reached").
    3. Check available capital. Do not approve a trade if it would require more than 10% of available capital as premium.
    4. Do NOT calculate exact position sizing yourself — actual order quantity is computed by
       Capital::Allocator. Return position_size_multiplier as an advisory risk-scaling cap
       (0.0-1.0) only; it is not the final quantity.
  PROMPT

  user_prompt 'Assess risk for the proposed strategy: %<strategy_details>s'

  schema do
    string :verdict, description: 'Risk verdict: APPROVED or REJECTED'
    number :max_risk_rupees, description: 'Maximum risk allowed in Rupees'
    number :position_size_multiplier, description: 'Size multiplier (0.0 to 1.0) based on risk environment'
    string :notes, description: 'Risk notes and rationale'
  end
end
