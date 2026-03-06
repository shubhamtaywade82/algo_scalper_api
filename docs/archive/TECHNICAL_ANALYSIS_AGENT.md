# Technical Analysis Agent

An AI-powered technical analysis agent that integrates with your trading system's instruments, indicators, DhanHQ client, and trading tools.

## Overview

The Technical Analysis Agent uses **function calling** (tool use) to interact with your trading system. It can:

- Fetch real-time market data (LTP, OHLC) for indices and instruments
- Calculate technical indicators (RSI, MACD, ADX, Supertrend, ATR, etc.)
- Analyze option chains and derivative data
- Query historical price data
- Get current positions and trading statistics

## Quick Start

```bash
# Ask a question about the market
bundle exec rake ai:technical_analysis["What is the current RSI for NIFTY?"]

# Analyze option chain
bundle exec rake ai:technical_analysis["Analyze BANKNIFTY option chain for bullish trades"]

# Check positions
bundle exec rake ai:technical_analysis["What are my current positions and their PnL?"]

# Stream the response
STREAM=true bundle exec rake ai:technical_analysis["Analyze SENSEX with RSI and MACD"]

# See example prompts and capabilities
bundle exec rake ai:examples
```

## Available Tools

The agent has access to the following tools:

### 1. `get_index_ltp`
Get Last Traded Price (LTP) for an index (NIFTY, BANKNIFTY, SENSEX)

**Parameters:**
- `index_key` (string): Index key: NIFTY, BANKNIFTY, or SENSEX

**Example:**
```json
{
  "tool": "get_index_ltp",
  "arguments": {
    "index_key": "NIFTY"
  }
}
```

### 2. `get_instrument_ltp`
Get LTP for a specific instrument by security_id and segment

**Parameters:**
- `security_id` (string): Security ID of the instrument
- `segment` (string): Exchange segment (e.g., IDX_I, NSE_FNO)

### 3. `get_ohlc`
Get OHLC (Open, High, Low, Close) data for an instrument

**Parameters:**
- `security_id` (string): Security ID
- `segment` (string): Exchange segment

### 4. `calculate_indicator`
Calculate a technical indicator for an index

**Parameters:**
- `index_key` (string): Index key: NIFTY, BANKNIFTY, or SENSEX
- `indicator` (string): Indicator name: RSI, MACD, ADX, Supertrend, ATR, BollingerBands
- `period` (integer, optional): Period for the indicator (defaults vary by indicator)
- `interval` (string, optional): Timeframe: 1, 5, 15, 30, 60 (minutes) or daily (default: "1")

**Example:**
```json
{
  "tool": "calculate_indicator",
  "arguments": {
    "index_key": "NIFTY",
    "indicator": "RSI",
    "period": 14,
    "interval": "5"
  }
}
```

**Available Indicators:**
- **RSI** (Relative Strength Index): Default period 14
- **MACD** (Moving Average Convergence Divergence): Returns MACD line, signal line, and histogram
- **ADX** (Average Directional Index): Default period 14
- **Supertrend**: Default period 7, multiplier 3.0
- **ATR** (Average True Range): Default period 14

### 5. `get_historical_data`
Get historical price data (candles) for an instrument

**Parameters:**
- `security_id` (string): Security ID
- `segment` (string): Exchange segment
- `interval` (string): Timeframe: 1, 5, 15, 30, 60 (minutes) or daily
- `from_date` (string): Start date (YYYY-MM-DD, optional, defaults to 7 days ago)
- `to_date` (string): End date (YYYY-MM-DD, optional, defaults to today)

### 6. `analyze_option_chain`
Analyze option chain for an index and get best candidates

**Parameters:**
- `index_key` (string): Index key: NIFTY, BANKNIFTY, or SENSEX
- `direction` (string): "bullish" or "bearish" (default: "bullish")
- `limit` (integer): Number of candidates to return (default: 5)

**Example:**
```json
{
  "tool": "analyze_option_chain",
  "arguments": {
    "index_key": "BANKNIFTY",
    "direction": "bullish",
    "limit": 5
  }
}
```

### 7. `get_trading_stats`
Get current trading statistics (win rate, PnL, positions)

**Parameters:**
- `date` (string, optional): Date in YYYY-MM-DD format (defaults to today)

### 8. `get_active_positions`
Get currently active trading positions

**Parameters:** None

## How It Works

1. **User Query**: You ask a question in natural language
2. **Tool Detection**: The AI analyzes your query and determines which tools to use
3. **Tool Execution**: The agent executes the tools and gathers data
4. **Analysis**: The AI analyzes the tool results and provides insights
5. **Response**: You receive a comprehensive analysis based on real data

## Getting Help

To see example prompts and what the agent can do:

```bash
bundle exec rake ai:examples
```

This will show:
- Example prompts organized by category
- Available tools
- Usage instructions

## Example Queries

### Market Data
```bash
# Get current NIFTY price
bundle exec rake ai:technical_analysis["What is the current NIFTY price?"]

# Get OHLC for BANKNIFTY
bundle exec rake ai:technical_analysis["Get today's OHLC data for BANKNIFTY"]
```

### Technical Indicators
```bash
# Calculate RSI
bundle exec rake ai:technical_analysis["What is the RSI for NIFTY on 5-minute timeframe?"]

# Multiple indicators
bundle exec rake ai:technical_analysis["Calculate RSI, MACD, and ADX for BANKNIFTY"]

# Supertrend analysis
bundle exec rake ai:technical_analysis["What is the Supertrend signal for SENSEX?"]
```

### Option Chain Analysis
```bash
# Bullish options
bundle exec rake ai:technical_analysis["Analyze NIFTY option chain for bullish trades"]

# Bearish options
bundle exec rake ai:technical_analysis["Find best bearish option candidates for BANKNIFTY"]
```

### Trading Statistics
```bash
# Current stats
bundle exec rake ai:technical_analysis["What are my current trading statistics?"]

# Positions
bundle exec rake ai:technical_analysis["Show me my active positions and their PnL"]

# Combined analysis
bundle exec rake ai:technical_analysis["Analyze my trading performance and suggest improvements based on current market conditions"]
```

### Complex Analysis
```bash
# Multi-step analysis
bundle exec rake ai:technical_analysis["Check NIFTY RSI and MACD, then analyze option chain if indicators are bullish"]

# Market condition assessment
bundle exec rake ai:technical_analysis["Assess current market conditions for NIFTY using RSI, ADX, and Supertrend"]
```

## Streaming Responses

Enable streaming for real-time responses:

```bash
STREAM=true bundle exec rake ai:technical_analysis["Analyze NIFTY with all indicators"]
```

## Integration with Existing System

The agent integrates seamlessly with:

- **Instruments**: Uses `Instrument` model and `InstrumentHelpers` concern
- **DhanHQ Client**: Uses `DhanHQ::Models::MarketFeed` and `DhanHQ::Models::HistoricalData`
- **Indicators**: Uses `CandleSeries` methods and `Indicators::Calculator`
- **Option Chains**: Uses `Options::DerivativeChainAnalyzer`
- **Trading Data**: Uses `PositionTracker` model

## Architecture

```
User Query
    ↓
TechnicalAnalysisAgent
    ↓
AI Model (Ollama/OpenAI)
    ↓
Tool Call Detection
    ↓
Tool Execution
    ├─→ get_index_ltp
    ├─→ calculate_indicator
    ├─→ analyze_option_chain
    └─→ ... (other tools)
    ↓
Tool Results
    ↓
AI Analysis
    ↓
Final Response
```

## Configuration

The agent uses the same AI configuration as other AI services:

- **Provider**: Automatically selected (Ollama if `OLLAMA_BASE_URL` is set, otherwise OpenAI)
- **Model**: Auto-selected best model for Ollama, or `gpt-4o` for OpenAI
- **Timeout**: Configurable via `OLLAMA_TIMEOUT` environment variable

See [AI Integration Guide](./AI_INTEGRATION.md) for configuration details.

## Limitations

1. **Tool Call Format**: The agent uses JSON-based tool calling. Some models may not format tool calls perfectly.
2. **Iteration Limit**: Maximum 5 tool calls per query to prevent infinite loops
3. **Data Freshness**: Uses cached candle data by default (configurable via `data_freshness` in `algo.yml`)

## Future Enhancements

- Support for more indicators (Bollinger Bands, Stochastic, etc.)
- Real-time WebSocket data integration
- Backtesting capabilities
- Strategy optimization suggestions
- Multi-timeframe analysis
