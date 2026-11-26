# Agent Tools

This directory contains tools that LLM agents use to interact with domain services, market data, and portfolio state. Tools inherit from `RubyLLM::Tool` (RubyLLM 2.x).

## Current Tools

- `GetMarketContextTool`: Fetches LTP, OHLC, standard technical indicators (RSI, MACD, ADX, Supertrend, ATR, Bollinger Bands), and SMC market structure (Order Blocks, FVGs, liquidity pools) for an index.
- `GetOptionChainTool`: Fetches option chain contracts (CE/PE), strike prices, Greeks, IV, and OI for an index filtered by bias.
- `GetAccountStatusTool`: Fetches available capital, trading statistics, and active positions from `PositionTracker`.

## Creating a Tool

Create a class inheriting from `RubyLLM::Tool`:

```ruby
class SearchMarketDataTool < RubyLLM::Tool
  description "Fetches recent candle data and market indicators for an index symbol."

  parameter :index_key, type: :string, description: "Index symbol (e.g., NIFTY, BANKNIFTY)", required: true
  parameter :interval,  type: :string, description: "Candle interval in minutes (e.g., 1, 5, 15)", required: false

  def execute(index_key:, interval: "5")
    # Fetch data from domain services
    { index: index_key.upcase, interval: interval, timestamp: Time.current }
  rescue StandardError => e
    { error: "Failed to fetch data: #{e.message}" }
  end
end
```

## Tool Parameter DSL Reference

### `description`
Human-readable description explaining what the tool does. The LLM uses this to decide when to invoke the tool.

```ruby
description "Fetches option chain contracts and Greeks for an index based on trading bias."
```

### `parameter`
Defines parameters accepted by the tool:

```ruby
parameter :index_key, type: :string, description: "Index symbol", required: true
parameter :limit,     type: :integer, description: "Max candidate contracts", required: false
```

**Supported parameter types:**
- `:string` - Text values
- `:integer` - Whole numbers
- `:number` - Decimal values
- `:boolean` - true/false
- `:array` - Lists of values
- `:object` - Key-value maps

### `execute`
Receives keyword arguments matching declared parameters. Must return a Hash or JSON-serializable structure. Always rescue domain errors and return `{ error: e.message }` rather than crashing the LLM turn.

## Registering Tools with Agents

Register tools on an agent using the `tools` macro:

```ruby
class MarketAnalystAgent < ApplicationAgent
  tools GetMarketContextTool
  ...
end
```

## Testing Tools

Unit test tools in `spec/tools/*_spec.rb`:

```ruby
RSpec.describe GetMarketContextTool do
  it 'inherits from RubyLLM::Tool and provides description' do
    expect(described_class).to be < RubyLLM::Tool
    expect(described_class.description).to be_present
  end
end
```
