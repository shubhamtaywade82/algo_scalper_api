# Agent Refactor Summary

## Overview

The Technical Analysis Agent has been refactored into an **intent-aware, tool-augmented, micro-step ReAct agent** following the mandate in `CURSOR_REFACTOR_MANDATE.md`.

## What Changed

### ✅ New Orchestration Layer (Added)

Five new modules were created to orchestrate the agent loop:

1. **`intent_resolver.rb`** - Single-purpose LLM call to extract intent from query
2. **`agent_context.rb`** - Stores structured facts (not raw JSON)
3. **`decision_engine.rb`** - Rule-based tool selection (Rails-controlled, not LLM)
4. **`adaptive_controller.rb`** - Self-correcting logic with payload reduction
5. **`agent_runner.rb`** - Main orchestration loop

### ✅ Enhanced Tools Module

Added wrapper methods that wrap existing tools with narrowing logic:
- `tool_resolve_instrument` - Rails-controlled instrument resolution
- `tool_get_ltp` - Get LTP for resolved instrument
- `tool_fetch_candles` - Fetch candles (narrowed to last 50)
- `tool_compute_indicators` - Aggregate ALL indicators in one call
- `tool_fetch_option_chain` - Fetch option chain (filtered to ATM ±1 ±2)
- `tool_check_data_availability` - Check data availability

### ✅ Updated Tool Registry

Added coarse-grained tools to registry:
- `resolve_instrument` - Preferred over manual instrument lookup
- `get_ltp` - Preferred over `get_instrument_ltp`
- `fetch_candles` - Preferred over `get_historical_data`
- `compute_indicators` - Preferred over individual `calculate_indicator` calls
- `fetch_option_chain` - Preferred over `analyze_option_chain` (with filtering)

**Legacy tools are still available** for backward compatibility.

### ✅ Updated Main Agent

The `TechnicalAnalysisAgent#analyze` method now:
- Uses `AgentRunner` by default (controlled by `AI_USE_AGENT_RUNNER` env var)
- Falls back to old `ConversationExecutor` if disabled
- Returns compatible response format

## What Was Preserved

### ✅ All Existing Code (DO NOT TOUCH)

- ✅ `Instrument` model and `InstrumentHelpers` concern
- ✅ `Derivative` model
- ✅ `CandleExtension` concern
- ✅ `DhanhqErrorHandler` module
- ✅ All existing tool implementations in `Tools` module
- ✅ All services (`IndexTechnicalAnalyzer`, `Options::ChainAnalyzer`, etc.)
- ✅ All indicator computation logic
- ✅ All DhanHQ integrations

**Nothing was deleted or rewritten.**

## How It Works

### Flow

1. **Intent Resolution** (LLM - small call)
   - Extracts: symbol, intent, derivatives_needed, timeframe_hint, confidence
   - NO data fetching, NO instrument resolution

2. **Agent Loop** (Rails-controlled)
   - DecisionEngine decides next tool (deterministic)
   - ONE tool called per iteration
   - AdaptiveController reduces/narrows payload
   - AgentContext stores facts only (not raw JSON)
   - Loop continues until sufficient data or abort

3. **Final Reasoning** (LLM - compact facts only)
   - Receives aggregated indicators
   - Receives filtered strikes (ATM ±1 ±2 for options)
   - Receives resolved instrument info
   - NO raw OHLC arrays, NO full option chains

### Example: "Analyse NIFTY for options buying"

1. Intent: `{ intent: :options_buying, symbol: "NIFTY", confidence: 0.9 }`
2. DecisionEngine: Resolve NIFTY → INDEX segment
3. DecisionEngine: Get LTP
4. DecisionEngine: Fetch option chain
5. AdaptiveController: Filter to ATM ±1 ±2 (reduces from 100+ to 5 strikes)
6. DecisionEngine: Compute indicators (5m, 15m)
7. Final reasoning: LLM receives compact facts only

## Configuration

### Environment Variables

- `AI_USE_AGENT_RUNNER=true` - Enable new orchestration layer (default: true)
- `AI_AGENT_MAX_ITERATIONS=15` - Max iterations in agent loop
- `AI_MAX_PAYLOAD_SIZE=2000` - Max payload size before reduction
- `AI_MAX_AMBIGUITY_PASSES=2` - Max ambiguity passes before narrowing
- `AI_MAX_REPEAT_STEPS=3` - Max repeated steps before abort

## Benefits

1. **Faster Progress** - One tool per iteration, deterministic decisions
2. **No Stalling** - Adaptive controller detects and prevents loops
3. **Smaller Prompts** - Payload reduction, filtered data
4. **Better Intent Handling** - Separate intent resolution from execution
5. **Rails-Controlled** - Instrument resolution, strike filtering done in Rails
6. **Backward Compatible** - Old executor still available via env var

## Testing

To test the new agent:

```ruby
# Enable new agent runner (default)
ENV['AI_USE_AGENT_RUNNER'] = 'true'

# Test intent resolution
agent = Services::Ai::TechnicalAnalysisAgent.new
result = agent.analyze(query: "Analyse NIFTY for options buying", stream: false)

# Check result
puts result[:verdict] # Should be 'ANALYSIS_COMPLETE' or 'NO_TRADE'
puts result[:iterations] # Number of iterations
puts result[:context] # Compact context summary
```

## Migration Notes

- **No breaking changes** - Old code still works
- **Gradual migration** - Can disable new runner via `AI_USE_AGENT_RUNNER=false`
- **Same API** - `analyze(query:, stream:)` method signature unchanged
- **Response format** - Compatible with old executor response

## Files Created

- `lib/services/ai/technical_analysis_agent/intent_resolver.rb`
- `lib/services/ai/technical_analysis_agent/agent_context.rb`
- `lib/services/ai/technical_analysis_agent/decision_engine.rb`
- `lib/services/ai/technical_analysis_agent/adaptive_controller.rb`
- `lib/services/ai/technical_analysis_agent/agent_runner.rb`

## Files Modified

- `lib/services/ai/technical_analysis_agent/tools.rb` - Added wrapper methods
- `lib/services/ai/technical_analysis_agent/tool_registry.rb` - Added coarse-grained tools
- `lib/services/ai/technical_analysis_agent.rb` - Integrated AgentRunner

## Next Steps

1. Test with various queries (swing trading, options buying, intraday)
2. Monitor performance and adjust timeouts if needed
3. Tune decision engine rules based on real usage
4. Gradually migrate from old executor to new runner

---

**Status**: ✅ Implementation Complete
**Backward Compatible**: ✅ Yes
**Breaking Changes**: ❌ None
