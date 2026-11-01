# frozen_string_literal: true

# Selects the best option contract strike and type from the option chain based
# on directional strategy and current price.
class OptionSelectorAgent < ApplicationAgent
  tools GetOptionChainTool

  inputs :index_key, :direction

  instructions <<~PROMPT
    You are the Option Selector Agent for an options trading bot.
    Your job is to select the single best option contract to trade based on the index and trading direction bias.
    Use the `GetOptionChainTool` tool to retrieve the current active options candidates.
    Select:
    1. The contract that is closest to ATM (At-The-Money) or slightly OTM (Out-of-the-Money), depending on liquidity and spread.
    2. Ensure the selected contract has high scoring/liquidity.
  PROMPT

  user_prompt 'Select the best option contract for %<index_key>s with a %<direction>s bias.'

  schema do
    string :selected_contract, description: 'The full symbol name of the selected option contract'
    number :strike, description: 'Strike price of the option'
    string :option_type, description: 'Option type: CE or PE'
    number :premium, description: 'Current premium/LTP of the contract'
    string :rationale, description: 'Short rationale for picking this strike'
  end
end
