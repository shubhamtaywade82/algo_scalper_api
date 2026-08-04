# frozen_string_literal: true

class StrategyAgent < ApplicationAgent
  description "Formulates a trading strategy based on market analysis, defining directional bias, target zones, entry triggers, SL, and TP."

  param :index_key, required: true
  param :market_analysis, required: true

  system <<~PROMPT
    You are the Strategy Agent for an options trading bot.
    Your job is to formulate a clear, actionable trading strategy for the index based on the Market Analyst's report.
    Use the following rules:
    - If the bias is BULLISH, formulate a long/CALL strategy.
    - If the bias is BEARISH, formulate a short/PUT strategy.
    - If the bias is NEUTRAL, or the trend is weak, or there is no clear confluence, do NOT trade (action: NO_TRADE).

    Define:
    1. Action: BUY_CALL, BUY_PUT, or NO_TRADE.
    2. Entry Trigger: Under what condition or price level to enter the trade (e.g., tap into an Order Block, break of structure).
    3. Stop Loss (SL): The logical invalidation level (e.g., above/below the Order Block).
    4. Take Profit (TP): The target level (e.g., next liquidity pool or key level).
    5. Max Holding Time: Time-based exit limit (e.g., exit after 20 minutes if price consolidates to prevent Theta decay).
    6. Trailing Rules: Guidelines on trailing the stop loss to lock in profits.
  PROMPT

  user "Formulate a strategy for {index_key} based on the market analysis: {market_analysis}"

  returns do
    string :action, description: "Trading action: BUY_CALL, BUY_PUT, or NO_TRADE"
    string :entry_trigger, description: "Condition or price level to enter the trade"
    number :stop_loss, description: "Stop loss price level (absolute index price)"
    number :take_profit, description: "Take profit price level (absolute index price)"
    string :max_holding_time, description: "Maximum time limit or exit conditions (to guard against Theta decay)"
    string :trailing_rules, description: "Rules for trailing the stop loss"
    string :rationale, description: "Short explanation for this strategy"
  end
end
