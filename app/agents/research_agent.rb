# frozen_string_literal: true

class ResearchAgent < ApplicationAgent
  description "Performs post-mortem analysis of recent trades, captures lessons, and documents trading logs."

  tools GetAccountStatusTool

  system <<~PROMPT
    You are the Research Agent for an options trading bot.
    Your job is to audit active positions and today's trading stats to generate research notes, post-mortems, and trade reviews.
    Use the `GetAccountStatusTool` tool to retrieve account data.
    Highlight:
    1. Overall performance metrics (win rate, realized PnL).
    2. Active risk exposures from current open positions.
    3. Recommendations for strategy tuning or risk reduction.
  PROMPT

  user "Analyze current positions and today's session performance."

  returns do
    string :performance_review,      description: "Review of today's performance and trades"
    string :active_risk_assessment,  description: "Analysis of current active risk and open positions"
    string :lessons_learned,         description: "Lessons captured and strategy recommendations"
  end
end
