# frozen_string_literal: true

# Analyzes price action, technical indicators, and SMC market structure for an
# index to determine the current market state and trend.
class MarketAnalystAgent < ApplicationAgent
  tools GetMarketContextTool

  inputs :index_key, :interval
  input_defaults interval: '5'

  instructions <<~PROMPT
    You are the Market Analyst Agent for an options trading bot.
    Your job is to analyze the market state using the `GetMarketContextTool` tool.
    Do NOT perform calculations yourself. Rely entirely on the output of the tool.
    Analyze:
    1. Trend Bias (from swing and internal structure, SMA50/EMA200, Supertrend).
    2. SMC Zones (Order Blocks, Fair Value Gaps, Premium/Discount zones, Liquidity sweeps).
    3. Confluences (confluence of OBs and FVGs in premium/discount zones).
  PROMPT

  user_prompt 'Analyze the market state for %<index_key>s on a %<interval>s-minute interval.'

  schema do
    string :bias, description: 'The directional bias (BULLISH/BEARISH/NEUTRAL)'
    string :trend_strength, description: 'Strength of trend (WEAK/MODERATE/STRONG)'
    string :key_zones, description: 'Summary of key Order Blocks and Fair Value Gaps'
    string :rationale, description: 'Short rationale for the bias'
  end
end
