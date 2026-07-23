# frozen_string_literal: true

class OptionSelectorAgent < ApplicationAgent
  description "Selects the best option contract strike and type from the option chain based on directional strategy and current price."

  tools GetOptionChainTool

  param :index_key, required: true
  param :direction, required: true

  system <<~PROMPT
    You are the Option Selector Agent for an options trading bot.
    Your job is to select the single best option contract to trade based on the index and trading direction bias.
    Use the `GetOptionChainTool` tool to retrieve the current active options candidates.
    Select:
    1. The contract that is closest to ATM (At-The-Money) or slightly OTM (Out-of-the-Money), depending on liquidity and spread.
    2. Ensure the selected contract has high scoring/liquidity.
  PROMPT

  user "Select the best option contract for {index_key} with a {direction} bias."

  returns do
    string :selected_contract, description: "The full symbol name of the selected option contract"
    number :strike, description: "Strike price of the option"
    string :option_type, description: "Option type: CE or PE"
    number :premium, description: "Current premium/LTP of the contract"
    string :rationale, description: "Short rationale for picking this strike"
  end
end
