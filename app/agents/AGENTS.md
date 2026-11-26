# Agents

This directory contains LLM-powered agents built on RubyLLM 2.x (`RubyLLM::Agent`). All agents in this application inherit from `ApplicationAgent`.

## Current Agents

- `MarketAnalystAgent`: Analyzes price action, technical indicators, and SMC structure for an index. Uses `GetMarketContextTool`.
- `OptionSelectorAgent`: Selects the single best option contract (ATM/OTM, liquidity, spread). Uses `GetOptionChainTool`.
- `StrategyAgent`: Formulates directional strategy, triggers, SL, and TP (advisory).
- `RiskAgent`: Evaluates strategy against active positions, margins, and portfolio caps. Uses `GetAccountStatusTool`.
- `ResearchAgent`: Audits active positions and daily performance for post-mortem analysis. Uses `GetAccountStatusTool`.

## Creating an Agent

Extend `ApplicationAgent` and declare inputs, prompt, tools, and schema:

```ruby
class MyAgent < ApplicationAgent
  tools GetMarketContextTool

  inputs :index_key, :interval
  input_defaults interval: '5'

  instructions <<~PROMPT
    You are an expert trading assistant. Use the tools provided to answer questions.
    Rely entirely on tool output and do not calculate technical levels manually.
  PROMPT

  user_prompt 'Analyze the market state for %<index_key>s on a %<interval>s-minute interval.'

  schema do
    string :bias, description: 'Directional bias: BULLISH, BEARISH, or NEUTRAL'
    string :confidence, description: 'Confidence level: HIGH, MODERATE, or LOW'
    string :rationale, description: 'Reasoning behind the verdict'
  end
end
```

## Running Agents

```ruby
# Single-turn call returning parsed schema Hash
result = MyAgent.call(index_key: 'NIFTY')
# => { "bias" => "BULLISH", "confidence" => "HIGH", "rationale" => "..." }

# Low-level turn returning RubyLLM::Message
message = MyAgent.new(index_key: 'NIFTY').ask('Analyze the market state for NIFTY on a 5-minute interval.')
message.parsed # parsed JSON output
```

## Configuration & Model Resolution

All agents resolve their model and provider via `LLMSettings`:
- Local Ollama (`http://localhost:11434/v1`): default model `llama3.2:3b`
- Ollama Cloud (`https://ollama.com/v1`): default model `minimax-m2.5`
- Global timeouts, retries, and logging are configured in `config/initializers/ruby_llm.rb`.

## Testing Agents

Test agent definitions and schema/tool integrations with RSpec and WebMock:

```ruby
RSpec.describe MyAgent do
  it 'declares inputs and tools' do
    expect(described_class.inputs).to eq([:index_key, :interval])
    expect(described_class.tools).to eq([GetMarketContextTool])
  end
end
```
