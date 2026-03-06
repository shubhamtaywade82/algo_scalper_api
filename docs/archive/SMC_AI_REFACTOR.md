# SMC Scanner AI Analysis Refactor

## Overview

Refactored SMC scanner AI analysis to use **chat completion with conversation history** and **native tool calling** (Ollama's `/api/chat` with `tools` parameter), replacing the previous single-prompt approach.

## Changes

### 1. New Service: `Smc::AiAnalyzer`

**File**: `app/services/smc/ai_analyzer.rb`

A new service that:
- Uses chat completion with conversation history (maintains message context across iterations)
- Supports native tool calling (Ollama's `/api/chat` with `tools` parameter)
- Allows AI to fetch additional data via tools:
  - `get_current_ltp` - Get current price
  - `get_historical_candles` - Fetch historical candle data
  - `get_technical_indicators` - Get RSI, MACD, ADX, Supertrend, ATR
  - `get_option_chain` - Get option chain data for indices

**Features**:
- Maintains conversation history (up to 12 messages by default)
- Iterative analysis with tool calling (up to 10 iterations)
- Streaming support for real-time responses
- Tool result caching within conversation

### 2. Updated: `OpenAIClient`

**File**: `lib/services/ai/openai_client.rb`

Enhanced to support native tool calling:
- Added `tools` and `tool_choice` parameters to `chat()` method
- Updated message formatting to handle `tool_calls` and `tool` role messages
- Returns full response hash (with `content` and `tool_calls`) when tools are used
- Maintains backward compatibility (returns content string when no tools)

**Changes**:
- `format_messages_ruby_openai()` - Now handles tool_calls and tool messages
- `format_messages_openai_ruby()` - Now handles tool_calls and tool messages
- `extract_content_ruby_openai()` - Returns hash with `content` and `tool_calls`
- `extract_content_openai_ruby()` - Returns hash with `content` and `tool_calls`

### 3. Updated: `Smc::BiasEngine`

**File**: `app/services/smc/bias_engine.rb`

Simplified AI analysis methods:
- `analyze_with_ai()` - Now uses `Smc::AiAnalyzer`
- `analyze_with_ai_for_decision()` - Now uses `Smc::AiAnalyzer`
- Removed: `smc_ai_system_prompt()`, `build_smc_analysis_prompt()`, `ai_client()`, `select_ai_model()`

### 4. Updated: `SendSmcAlertJob`

**File**: `app/jobs/notifications/telegram/send_smc_alert_job.rb`

Simplified AI analysis:
- `fetch_ai_analysis()` - Now uses `Smc::AiAnalyzer`
- Removed: `smc_ai_system_prompt()`, `build_smc_analysis_prompt()`, `ai_client()`, `select_ai_model()`

## Benefits

1. **Better Context**: Conversation history allows AI to build on previous analysis
2. **Dynamic Data Fetching**: AI can request additional data when needed via tools
3. **More Reliable**: Native tool calling is more reliable than text-based parsing
4. **Efficient**: AI only fetches data it actually needs
5. **Extensible**: Easy to add new tools for additional data sources

## Usage

The refactor is transparent - existing code continues to work:

```ruby
# In BiasEngine
engine = Smc::BiasEngine.new(instrument)
analysis = engine.analyze_with_ai

# In SendSmcAlertJob (automatic)
# Job automatically uses new AiAnalyzer
```

## Configuration

Environment variables:
- `SMC_AI_MAX_ITERATIONS` - Max conversation iterations (default: 10)
- `SMC_AI_MAX_MESSAGE_HISTORY` - Max messages to keep (default: 12)

## Tool Calling Flow

1. AI receives initial SMC data
2. AI can call tools to fetch additional data:
   - Current LTP
   - Historical candles
   - Technical indicators
   - Option chain data
3. Tool results are added to conversation
4. AI provides final analysis based on all data

## Backward Compatibility

- Existing code continues to work
- When tools are not used, `chat()` returns content string (as before)
- When tools are used, `chat()` returns hash with `content` and `tool_calls`

## Testing

To test the new implementation:

```ruby
# In Rails console
instrument = Instrument.find_by_sid_and_segment(security_id: "13", segment_code: "IDX_I")
engine = Smc::BiasEngine.new(instrument)
details = engine.details

analyzer = Smc::AiAnalyzer.new(instrument, initial_data: details)
analysis = analyzer.analyze

# Or with streaming
analyzer.analyze(stream: true) do |chunk|
  print chunk
end
```

## Future Enhancements

- Add more tools (e.g., `get_order_flow`, `get_volume_profile`)
- Support for multi-instrument analysis
- Caching of tool results across different analyses
- Custom tool definitions per analysis type
