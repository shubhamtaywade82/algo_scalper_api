# 📌 CURSOR REFACTOR MANDATE
## Trading Analysis Agent – Intent-Aware, Tool-Augmented, Micro-Step Loop

> **Instruction to Cursor AI**
>
> Analyze the existing Rails codebase and refactor it into an intent-aware, tool-augmented, micro-step ReAct trading analysis agent.
>
> **CRITICAL**: Preserve all existing DhanHQ integrations, models, concerns, caching, and indicator logic.
>
> **DO NOT** rewrite market data logic.
>
> Introduce a new orchestration layer that controls how the LLM reasons, when tools are called, how ambiguity is resolved, and how data is progressively narrowed before reasoning.

---

## 1️⃣ FIRST: ANALYZE CURRENT IMPLEMENTATION (MANDATORY)

Before changing anything, Cursor must identify:

### A. Existing Strengths (DO NOT TOUCH)

**Models & Concerns** (in `app/models/` and `app/models/concerns/`):
- ✅ `Instrument` model with `InstrumentHelpers` concern
- ✅ `Derivative` model
- ✅ `CandleExtension` concern (provides `candles()`, `rsi()`, `macd()`, etc.)
- ✅ `InstrumentHelpers` concern (provides `ltp()`, `intraday_ohlc()`, `ohlc()`)
- ✅ `DhanhqErrorHandler` module (error handling for DhanHQ API)

**Services** (in `app/services/`):
- ✅ `IndexConfigLoader` - loads index configurations
- ✅ `IndexInstrumentCache` - caches instrument lookups
- ✅ `IndexTechnicalAnalyzer` - computes indicators for indices
- ✅ `Options::ChainAnalyzer` - option chain analysis
- ✅ All indicator services in `app/services/indicators/`

**AI Agent Current Structure** (in `lib/services/ai/technical_analysis_agent/`):
- ✅ `Tools` module - all tool implementations (DO NOT DELETE)
- ✅ `ToolRegistry` module - tool definitions (KEEP, but refactor)
- ✅ `ToolExecutor` module - tool execution logic (KEEP)
- ✅ `ConversationExecutor` module - conversation loop (REFACTOR, don't replace)
- ✅ `Helpers` module - symbol detection, token estimation (KEEP)
- ✅ `Learning` module - error learning patterns (KEEP)
- ✅ `PromptBuilder` module - prompt construction (REFACTOR)

**These are implementation assets, not problems. DO NOT DELETE OR REWRITE THEM.**

---

### B. Current Problems (TO FIX)

Cursor must locate and flag these architectural violations:

#### Problem 1: LLM Does Too Much in One Step
**Location**: `lib/services/ai/technical_analysis_agent/tools.rb`
- ❌ `tool_get_comprehensive_analysis` - fetches everything in one call (LTP + candles + ALL indicators)
- ❌ LLM receives massive JSON responses with raw OHLC data
- ❌ No progressive narrowing - all data dumped at once

**Fix**: Break into micro-steps with narrowing.

---

#### Problem 2: No Intent Resolution
**Location**: `lib/services/ai/technical_analysis_agent.rb` (analyze method)
- ❌ LLM receives full query without intent extraction
- ❌ No distinction between swing trading, options buying, intraday
- ❌ LLM must guess what user wants

**Fix**: Add intent resolver before main loop.

---

#### Problem 3: Instrument Resolution is LLM-Guided
**Location**: `lib/services/ai/technical_analysis_agent/tools.rb` (tool_get_instrument_ltp, tool_get_comprehensive_analysis)
- ❌ LLM chooses exchange/segment (can be wrong)
- ❌ Auto-detection exists but LLM can override incorrectly
- ❌ No deterministic disambiguation

**Fix**: Rails-controlled instrument resolution.

---

#### Problem 4: Option Chain Overload
**Location**: `lib/services/ai/technical_analysis_agent/tools.rb` (tool_analyze_option_chain)
- ❌ Full option chain JSON passed to LLM
- ❌ No strike filtering before LLM sees data
- ❌ LLM must process hundreds of strikes

**Fix**: Filter to ATM ±1 ±2 before LLM reasoning.

---

#### Problem 5: No Adaptive Control
**Location**: `lib/services/ai/technical_analysis_agent/conversation_executor.rb`
- ❌ Loop continues blindly if response is ambiguous
- ❌ No payload size reduction logic
- ❌ No detection of repeating states

**Fix**: Add adaptive controller.

---

#### Problem 6: Tool Registry is Too Granular
**Location**: `lib/services/ai/technical_analysis_agent/tool_registry.rb`
- ❌ Individual indicator tools (`calculate_indicator`, `calculate_advanced_indicator`)
- ❌ LLM can call indicators one-by-one inefficiently
- ❌ No coarse-grained indicator computation

**Fix**: Aggregate indicators into single tool calls.

---

## 2️⃣ ADD NEW ORCHESTRATION LAYER (DO NOT MIX WITH MODELS)

Cursor must create this **new AI orchestration layer**:

```
lib/services/ai/technical_analysis_agent/
  ├── intent_resolver.rb          # NEW - Extract intent from query
  ├── agent_context.rb            # NEW - Store facts, not raw data
  ├── decision_engine.rb          # NEW - Rule-based tool selection
  ├── adaptive_controller.rb      # NEW - Self-correcting logic
  └── agent_runner.rb             # NEW - Main orchestration loop
```

**CRITICAL**: This layer **wraps** existing logic — it does not replace it.

**DO NOT**:
- ❌ Move `Instrument` model logic into orchestration layer
- ❌ Move `CandleExtension` methods into orchestration layer
- ❌ Move DhanHQ calls into orchestration layer
- ❌ Delete existing `Tools` module

**DO**:
- ✅ Call existing tool methods from orchestration layer
- ✅ Use existing models/concerns from orchestration layer
- ✅ Wrap existing tools with narrowing logic

---

## 3️⃣ INTENT RESOLVER (LLM – SINGLE PURPOSE)

### File: `lib/services/ai/technical_analysis_agent/intent_resolver.rb`

### Responsibility
One small LLM call to extract ONLY:
- `underlying_symbol` (string) - e.g., "NIFTY", "RELIANCE"
- `intent` (enum) - `:swing_trading`, `:options_buying`, `:intraday`, `:general`
- `derivatives_needed` (boolean) - whether options/derivatives analysis needed
- `timeframe_hint` (string) - "5m", "15m", "1h", "daily"
- `confidence` (float) - 0.0 to 1.0

### Implementation Rules

```ruby
module Services
  module Ai
    class TechnicalAnalysisAgent
      module IntentResolver
        def resolve_intent(query)
          # Small prompt - ONLY intent extraction
          prompt = <<~PROMPT
            Extract trading intent from query. Respond with JSON only:
            {
              "underlying_symbol": "NIFTY" | "RELIANCE" | null,
              "intent": "swing_trading" | "options_buying" | "intraday" | "general",
              "derivatives_needed": true | false,
              "timeframe_hint": "5m" | "15m" | "1h" | "daily",
              "confidence": 0.0-1.0
            }
          PROMPT

          # Single LLM call - NO tool calls
          response = @client.chat(
            messages: [
              { role: 'system', content: 'You are an intent extractor. Return JSON only.' },
              { role: 'user', content: prompt }
            ],
            model: model,
            temperature: 0.1 # Low temperature for consistency
          )

          # Parse JSON response
          JSON.parse(response)
        rescue JSON::ParserError, StandardError => e
          # Fallback: extract symbol only, default intent
          {
            underlying_symbol: extract_symbol_fallback(query),
            intent: :general,
            derivatives_needed: false,
            timeframe_hint: '15m',
            confidence: 0.3
          }
        end
      end
    end
  end
end
```

### Rules
- ✅ **NO** data fetching
- ✅ **NO** instrument resolution
- ✅ **NO** indicators
- ✅ **NO** tool calls
- ✅ **JSON output only**

If `confidence < 0.5` → DecisionEngine must branch deterministically, not stall.

---

## 4️⃣ AGENT CONTEXT (FACTS ONLY)

### File: `lib/services/ai/technical_analysis_agent/agent_context.rb`

### Responsibility
Store **structured facts**, not raw DhanHQ JSON.

### Structure

```ruby
module Services
  module Ai
    class TechnicalAnalysisAgent
      class AgentContext
        attr_accessor :intent, :underlying_symbol, :resolved_instrument,
                      :ltp, :filtered_strikes, :indicators, :tool_history,
                      :confidence, :derivatives_needed, :timeframe_hint

        def initialize(intent_data)
          @intent = intent_data[:intent]
          @underlying_symbol = intent_data[:underlying_symbol]
          @resolved_instrument = nil
          @ltp = nil
          @filtered_strikes = [] # Only ATM ±1 ±2 for options
          @indicators = {} # Aggregated, not raw
          @tool_history = []
          @confidence = intent_data[:confidence] || 0.0
          @derivatives_needed = intent_data[:derivatives_needed] || false
          @timeframe_hint = intent_data[:timeframe_hint] || '15m'
        end

        def add_observation(tool_name, tool_input, tool_result)
          # Store structured facts, not raw JSON
          observation = {
            tool: tool_name,
            input: tool_input,
            result: extract_facts(tool_result) # Extract only key facts
          }
          @tool_history << observation
        end

        def extract_facts(tool_result)
          # Extract only essential facts from tool result
          # DO NOT store raw OHLC arrays or full option chains
          case tool_result
          when Hash
            facts = {}
            facts[:ltp] = tool_result[:ltp] || tool_result['ltp'] if tool_result[:ltp] || tool_result['ltp']
            facts[:indicators] = aggregate_indicators(tool_result) if tool_result[:indicators] || tool_result['indicators']
            facts[:strikes] = filter_strikes_for_context(tool_result[:strikes]) if tool_result[:strikes]
            facts
          else
            tool_result
          end
        end

        def ready_for_analysis?
          # Check if we have minimum required data
          case @intent
          when :swing_trading
            @resolved_instrument && @ltp && @indicators.any?
          when :options_buying
            @resolved_instrument && @ltp && @filtered_strikes.any? && @indicators.any?
          when :intraday
            @resolved_instrument && @ltp && @indicators.any?
          else
            @resolved_instrument && @ltp
          end
        end
      end
    end
  end
end
```

### Hard Rule
**Raw DhanHQ JSON must NEVER be stored in AgentContext.**

Only store:
- ✅ Resolved instrument ID/symbol
- ✅ LTP (single number)
- ✅ Aggregated indicators (RSI: 62.1, MACD: bullish, etc.)
- ✅ Filtered strikes (ATM ±1 ±2 only for options)
- ✅ Tool history (what was called, not full results)

---

## 5️⃣ DECISION ENGINE (RULE-BASED, NOT LLM)

### File: `lib/services/ai/technical_analysis_agent/decision_engine.rb`

### Responsibility
Given current `AgentContext`, decide:
- Which tool to call next (deterministic, not LLM)
- Whether to narrow, expand, or abort
- Whether enough data exists to reason
- Whether to recheck or move forward

### Mandatory Rules Cursor Must Implement

#### Rule 1: Instrument Disambiguation

```ruby
def resolve_instrument_deterministically(context)
  symbol = context.underlying_symbol
  return nil unless symbol

  # Find all matching instruments
  candidates = Instrument.where(underlying_symbol: symbol.upcase)

  if candidates.count > 1
    # Disambiguate based on intent
    case context.intent
    when :swing_trading
      # Prefer EQUITY for swing trading
      candidates.find { |i| i.segment == 'equity' } || candidates.first
    when :options_buying
      # Prefer INDEX for options (NIFTY, BANKNIFTY) or stock underlying
      candidates.find { |i| i.segment == 'index' } ||
        candidates.find { |i| i.segment == 'equity' } ||
        candidates.first
    when :intraday
      # Prefer INDEX for intraday indices
      candidates.find { |i| i.segment == 'index' } || candidates.first
    else
      candidates.first
    end
  else
    candidates.first
  end
end
```

**NO LLM involvement here.**

---

#### Rule 2: Options Buying Narrowing

```ruby
def narrow_option_chain(context, full_chain_result)
  # Extract spot price
  spot = context.ltp || full_chain_result[:spot]
  return [] unless spot

  # Calculate ATM
  atm_strike = calculate_atm_strike(spot, full_chain_result[:strikes])

  # Filter to ATM ±1 ±2 only
  filtered = full_chain_result[:strikes].select do |strike|
    strike_diff = (strike[:strike] - atm_strike).abs
    strike_diff <= 2 # ATM, ATM±1, ATM±2
  end

  # Store filtered strikes in context
  context.filtered_strikes = filtered
  filtered
end
```

**LLM must NEVER see full option chain.**

---

#### Rule 3: Swing Trading Narrowing

```ruby
def narrow_for_swing_trading(context)
  # Force EQUITY segment
  if context.resolved_instrument&.segment != 'equity'
    context.resolved_instrument = Instrument
      .where(underlying_symbol: context.underlying_symbol)
      .where(segment: 'equity')
      .first
  end

  # Use higher timeframes (15m, 1h, daily)
  context.timeframe_hint = ['15m', '1h', 'daily'].find { |tf| tf == context.timeframe_hint } || '15m'

  # Ignore derivatives
  context.derivatives_needed = false
end
```

---

#### Rule 4: Tool Selection Logic

```ruby
def next_tool(context)
  # Step 1: Resolve instrument if not done
  return { tool: 'resolve_instrument', args: { symbol: context.underlying_symbol } } unless context.resolved_instrument

  # Step 2: Get LTP if not available
  return { tool: 'get_ltp', args: { instrument_id: context.resolved_instrument.id } } unless context.ltp

  # Step 3: Based on intent, fetch appropriate data
  case context.intent
  when :options_buying
    return { tool: 'fetch_option_chain', args: { instrument_id: context.resolved_instrument.id } } if context.filtered_strikes.empty?
    return { tool: 'compute_indicators', args: { instrument_id: context.resolved_instrument.id, timeframes: ['5m', '15m'] } } if context.indicators.empty?
  when :swing_trading
    return { tool: 'fetch_candles', args: { instrument_id: context.resolved_instrument.id, interval: context.timeframe_hint } } if context.indicators.empty?
    return { tool: 'compute_indicators', args: { instrument_id: context.resolved_instrument.id, timeframes: ['15m', '1h'] } } if context.indicators.empty?
  when :intraday
    return { tool: 'fetch_candles', args: { instrument_id: context.resolved_instrument.id, interval: '5m' } } if context.indicators.empty?
    return { tool: 'compute_indicators', args: { instrument_id: context.resolved_instrument.id, timeframes: ['5m', '15m'] } } if context.indicators.empty?
  end

  # Step 4: Ready for analysis
  return { tool: 'finalize', args: {} } if context.ready_for_analysis?

  # Default: abort if we can't determine next step
  { tool: 'abort', args: { reason: 'Cannot determine next step' } }
end
```

---

## 6️⃣ ADAPTIVE CONTROLLER (SELF-CORRECTING LOGIC)

### File: `lib/services/ai/technical_analysis_agent/adaptive_controller.rb`

### Responsibility
After every tool response, decide:
- Is the response too large?
- Is it ambiguous?
- Is it insufficient?
- Is it repeating a previous state?

### Rules Cursor Must Add

```ruby
module Services
  module Ai
    class TechnicalAnalysisAgent
      module AdaptiveController
        MAX_PAYLOAD_SIZE = 2000 # characters
        MAX_AMBIGUITY_PASSES = 2
        MAX_REPEAT_STEPS = 3

        def adapt_tool_result(context, tool_name, tool_result)
          # Rule 1: Reduce payload if too large
          if tool_result.to_json.length > MAX_PAYLOAD_SIZE
            tool_result = reduce_payload(tool_result, tool_name)
          end

          # Rule 2: Handle ambiguity
          if ambiguous?(tool_result) && context.ambiguity_passes >= MAX_AMBIGUITY_PASSES
            tool_result = narrow_deterministically(context, tool_result)
          end

          # Rule 3: Detect repeating states
          if repeating_step?(context, tool_name)
            return { error: 'NO_TRADE', reason: 'Repeating steps detected - insufficient data' }
          end

          tool_result
        end

        def reduce_payload(result, tool_name)
          case tool_name
          when 'fetch_option_chain'
            # Filter to ATM ±1 ±2 only
            narrow_option_chain(context, result)
          when 'fetch_candles', 'get_historical_data'
            # Keep only last N candles
            result[:candles] = result[:candles].last(50) if result[:candles]
            result
          when 'compute_indicators'
            # Aggregate indicators, remove raw data
            aggregate_indicators(result)
          else
            result
          end
        end

        def repeating_step?(context, tool_name)
          recent_tools = context.tool_history.last(MAX_REPEAT_STEPS).map { |h| h[:tool] }
          recent_tools.count(tool_name) >= MAX_REPEAT_STEPS
        end
      end
    end
  end
end
```

---

## 7️⃣ REFACTORED TOOL REGISTRY (COARSE-GRAINED)

### File: `lib/services/ai/technical_analysis_agent/tool_registry.rb` (REFACTOR)

### Current Problem
Too many granular tools - LLM can call indicators one-by-one.

### New Structure

**KEEP existing tools but wrap them:**

```ruby
def build_tools_registry
  {
    # Instrument Resolution (Rails-controlled)
    'resolve_instrument' => {
      description: 'Resolve instrument from symbol (Rails-controlled, not LLM choice)',
      parameters: [{ name: 'symbol', type: 'string' }],
      handler: method(:tool_resolve_instrument) # NEW wrapper
    },

    # Market State
    'get_ltp' => {
      description: 'Get Last Traded Price for resolved instrument',
      parameters: [{ name: 'instrument_id', type: 'integer' }],
      handler: method(:tool_get_ltp) # NEW wrapper around existing tool_get_instrument_ltp
    },

    # Historical Data (Narrowed)
    'fetch_candles' => {
      description: 'Fetch historical candles (automatically narrowed to last 50)',
      parameters: [
        { name: 'instrument_id', type: 'integer' },
        { name: 'interval', type: 'string' }
      ],
      handler: method(:tool_fetch_candles) # NEW wrapper
    },

    # Indicators (COARSE-GRAINED - All at once)
    'compute_indicators' => {
      description: 'Compute ALL indicators for instrument (RSI, MACD, ADX, Supertrend, ATR, BollingerBands)',
      parameters: [
        { name: 'instrument_id', type: 'integer' },
        { name: 'timeframes', type: 'array', description: 'Array of timeframes: ["5m", "15m"]' }
      ],
      handler: method(:tool_compute_indicators) # NEW - aggregates existing indicator tools
    },

    # Options (Narrowed)
    'fetch_option_chain' => {
      description: 'Fetch option chain (automatically filtered to ATM ±1 ±2)',
      parameters: [{ name: 'instrument_id', type: 'integer' }],
      handler: method(:tool_fetch_option_chain) # NEW wrapper around existing tool_analyze_option_chain
    },

    # Context
    'check_data_availability' => {
      description: 'Check if sufficient data exists for analysis',
      parameters: [],
      handler: method(:tool_check_data_availability) # NEW
    }
  }
end
```

### Implementation Rules

**DO NOT expose:**
- ❌ `calculate_indicator` (individual)
- ❌ `calculate_advanced_indicator` (individual)
- ❌ `get_historical_data` (too granular)
- ❌ `get_ohlc` (redundant with fetch_candles)

**DO expose:**
- ✅ `compute_indicators` (aggregated)
- ✅ `fetch_candles` (narrowed)
- ✅ `fetch_option_chain` (filtered)

---

## 8️⃣ AGENT RUNNER (THE LOOP)

### File: `lib/services/ai/technical_analysis_agent/agent_runner.rb`

### Required Loop Shape

```ruby
module Services
  module Ai
    class TechnicalAnalysisAgent
      module AgentRunner
        def run_agent_loop(query:, stream: false, &block)
          # Step 1: Resolve intent (LLM - small)
          intent_data = resolve_intent(query)
          context = AgentContext.new(intent_data)

          yield("🔍 Intent resolved: #{intent_data[:intent]} (#{intent_data[:confidence]})\n") if block_given?

          # Step 2-6: Loop until ready
          iteration = 0
          max_iterations = 15

          while iteration < max_iterations && !context.ready_for_analysis?
            iteration += 1

            # Step 2: Decide next step (Rails - deterministic)
            next_tool = decision_engine.next_tool(context)

            if next_tool[:tool] == 'abort'
              yield("⏹️  Aborting: #{next_tool[:args][:reason]}\n") if block_given?
              return { verdict: 'NO_TRADE', reason: next_tool[:args][:reason] }
            end

            if next_tool[:tool] == 'finalize'
              break # Ready for final reasoning
            end

            # Step 3: Call ONE tool
            yield("🔧 Calling: #{next_tool[:tool]}\n") if block_given?
            tool_result = execute_tool({ 'tool' => next_tool[:tool], 'arguments' => next_tool[:args] })

            # Step 4: Adapt / reduce / narrow
            tool_result = adaptive_controller.adapt_tool_result(context, next_tool[:tool], tool_result)

            # Step 5: Store facts (not raw data)
            context.add_observation(next_tool[:tool], next_tool[:args], tool_result)

            # Update context with extracted facts
            update_context_from_result(context, tool_result)

            # Step 6: Check if ready
            if context.ready_for_analysis?
              yield("✅ Sufficient data collected\n") if block_given?
              break
            end
          end

          # Step 7: Final LLM reasoning (compact facts only)
          final_analysis = synthesize_analysis(context, stream: stream, &block)

          {
            analysis: final_analysis,
            context: context.summary, # Compact summary, not full history
            iterations: iteration
          }
        end

        def update_context_from_result(context, tool_result)
          # Extract only essential facts
          context.ltp = tool_result[:ltp] || tool_result['ltp'] if tool_result[:ltp] || tool_result['ltp']
          context.indicators = aggregate_indicators(tool_result) if tool_result[:indicators]
          context.filtered_strikes = filter_strikes(tool_result[:strikes]) if tool_result[:strikes]
        end

        def synthesize_analysis(context, stream: false, &block)
          # Build compact prompt with facts only
          facts_prompt = build_facts_prompt(context)

          messages = [
            { role: 'system', content: build_synthesis_system_prompt },
            { role: 'user', content: facts_prompt }
          ]

          if stream && block_given?
            @client.chat_stream(messages: messages, model: model, temperature: 0.3, &block)
          else
            @client.chat(messages: messages, model: model, temperature: 0.3)
          end
        end

        def build_facts_prompt(context)
          # Compact facts only - NO raw data
          <<~PROMPT
            Analyze based on these facts:

            Instrument: #{context.resolved_instrument&.symbol_name}
            LTP: #{context.ltp}
            Intent: #{context.intent}

            Indicators:
            #{format_indicators_compact(context.indicators)}

            #{if context.filtered_strikes.any?
                "Option Strikes (ATM ±1 ±2):\n#{format_strikes_compact(context.filtered_strikes)}"
              else
                ''
              end}

            Provide trading analysis and recommendation.
          PROMPT
        end
      end
    end
  end
end
```

---

## 9️⃣ NEW TOOL WRAPPERS (WRAP EXISTING TOOLS)

### File: `lib/services/ai/technical_analysis_agent/tools.rb` (ADD NEW METHODS, KEEP EXISTING)

### Implementation Pattern

```ruby
# NEW wrapper - wraps existing tool_get_instrument_ltp
def tool_resolve_instrument(args)
  symbol = args['symbol'] || args[:symbol]
  return { error: 'Missing symbol' } unless symbol

  # Use DecisionEngine to resolve deterministically
  instrument = decision_engine.resolve_instrument_deterministically(
    AgentContext.new(intent: :general, underlying_symbol: symbol)
  )

  return { error: "Instrument not found: #{symbol}" } unless instrument

  {
    instrument_id: instrument.id,
    symbol: instrument.symbol_name,
    segment: instrument.segment,
    exchange: instrument.exchange
  }
end

# NEW wrapper - wraps existing tool_get_instrument_ltp
def tool_get_ltp(args)
  instrument_id = args['instrument_id'] || args[:instrument_id]
  return { error: 'Missing instrument_id' } unless instrument_id

  instrument = Instrument.find_by(id: instrument_id)
  return { error: "Instrument not found: #{instrument_id}" } unless instrument

  # Call existing method
  result = tool_get_instrument_ltp({
    'underlying_symbol' => instrument.underlying_symbol,
    'exchange' => instrument.exchange,
    'segment' => instrument.segment
  })

  # Extract only LTP
  { ltp: result[:ltp] || result['ltp'] }
end

# NEW - aggregates existing indicator tools
def tool_compute_indicators(args)
  instrument_id = args['instrument_id'] || args[:instrument_id]
  timeframes = args['timeframes'] || ['15m']

  instrument = Instrument.find_by(id: instrument_id)
  return { error: "Instrument not found: #{instrument_id}" } unless instrument

  indicators = {}
  timeframes.each do |tf|
    # Call existing indicator computation (from existing tools)
    normalized_tf = tf.gsub(/m$/, '')
    series = instrument.candles(interval: normalized_tf)
    next unless series

    indicators[tf] = {
      rsi: series.rsi(14),
      macd: series.macd(12, 26, 9),
      adx: series.adx(14),
      supertrend: series.supertrend_signal,
      atr: series.atr(14),
      bollinger: series.bollinger_bands(period: 20)
    }
  end

  { indicators: indicators }
end

# NEW wrapper - wraps existing tool_analyze_option_chain with narrowing
def tool_fetch_option_chain(args)
  instrument_id = args['instrument_id'] || args[:instrument_id]
  return { error: 'Missing instrument_id' } unless instrument_id

  instrument = Instrument.find_by(id: instrument_id)
  return { error: "Instrument not found: #{instrument_id}" } unless instrument

  # Call existing tool
  full_chain = tool_analyze_option_chain({
    'underlying_symbol' => instrument.underlying_symbol,
    'exchange' => instrument.exchange,
    'segment' => instrument.segment
  })

  # Narrow to ATM ±1 ±2
  spot = full_chain[:spot] || full_chain['spot']
  return full_chain unless spot

  atm = calculate_atm_strike(spot, full_chain[:strikes] || full_chain['strikes'])
  filtered = (full_chain[:strikes] || full_chain['strikes']).select do |s|
    (s[:strike] - atm).abs <= 2
  end

  {
    spot: spot,
    atm_strike: atm,
    strikes: filtered # Only ATM ±1 ±2
  }
end
```

**KEEP all existing tool methods** - they are still used by wrappers.

---

## 🔴 WHAT CURSOR MUST NOT DO

### ❌ DO NOT DELETE
- `app/models/instrument.rb`
- `app/models/concerns/instrument_helpers.rb`
- `app/models/concerns/candle_extension.rb`
- `lib/services/ai/technical_analysis_agent/tools.rb` (existing methods)
- `app/services/index_technical_analyzer.rb`
- `app/services/options/chain_analyzer.rb`

### ❌ DO NOT REWRITE
- DhanHQ API calls
- Indicator computation logic
- Caching mechanisms
- WebSocket LTP resolution

### ❌ DO NOT ALLOW LLM TO
- Choose instruments (Rails decides)
- Choose strikes (Rails filters)
- See raw OHLC arrays
- See full option chains
- Do multi-step reasoning in one call

### ❌ DO NOT CREATE
- New models (use existing)
- New concerns (use existing)
- Duplicate indicator logic (use existing)

---

## ✅ SUCCESS CRITERIA

After refactor, these queries must work:

### Query 1: "Analyse RELIANCE for swing trading"
1. Intent resolver: `{ intent: :swing_trading, symbol: "RELIANCE" }`
2. DecisionEngine: Resolve RELIANCE → EQUITY segment
3. DecisionEngine: Fetch 15m/1h candles
4. DecisionEngine: Compute indicators
5. Final reasoning: LLM receives compact facts only

### Query 2: "Analyse NIFTY for options buying"
1. Intent resolver: `{ intent: :options_buying, symbol: "NIFTY" }`
2. DecisionEngine: Resolve NIFTY → INDEX segment
3. DecisionEngine: Fetch option chain
4. AdaptiveController: Filter to ATM ±1 ±2
5. DecisionEngine: Compute indicators
6. Final reasoning: LLM receives filtered strikes + indicators

### Query 3: "What is the price of TCS?"
1. Intent resolver: `{ intent: :general, symbol: "TCS" }`
2. DecisionEngine: Resolve TCS → EQUITY
3. DecisionEngine: Get LTP
4. Final reasoning: Simple price response

### Agent Behavior
- ✅ Progresses fast (one tool per iteration)
- ✅ Self-corrects (adaptive controller)
- ✅ Never stalls (max iterations, abort conditions)
- ✅ Never overwhelms LLM (payload reduction)
- ✅ Always supports NO_TRADE (abort gracefully)

---

## 🏁 FINAL NOTE (IMPORTANT)

This refactor is **additive and surgical**, not destructive.

Cursor's job is to:
- **Wrap** existing tools with narrowing logic
- **Orchestrate** tool calls with Rails-controlled decisions
- **Discipline** the LLM with intent resolution and adaptive control

**DO NOT** rewrite the existing system.

---

## 📋 IMPLEMENTATION CHECKLIST

### Phase 1: Analysis (DO FIRST)
- [ ] Identify all existing models/concerns/services (DO NOT TOUCH)
- [ ] Flag all LLM calls that do too much
- [ ] Flag all places where raw data is passed to LLM
- [ ] Document current tool registry structure

### Phase 2: New Orchestration Layer
- [ ] Create `intent_resolver.rb`
- [ ] Create `agent_context.rb`
- [ ] Create `decision_engine.rb`
- [ ] Create `adaptive_controller.rb`
- [ ] Create `agent_runner.rb`

### Phase 3: Refactor Existing
- [ ] Refactor `tool_registry.rb` (coarse-grained tools)
- [ ] Add wrapper methods to `tools.rb` (keep existing)
- [ ] Refactor `conversation_executor.rb` to use AgentRunner
- [ ] Update `prompt_builder.rb` for synthesis prompts only

### Phase 4: Integration
- [ ] Update `technical_analysis_agent.rb` to use AgentRunner
- [ ] Test intent resolution
- [ ] Test instrument disambiguation
- [ ] Test option chain narrowing
- [ ] Test swing trading narrowing

### Phase 5: Validation
- [ ] Verify NO existing models/concerns deleted
- [ ] Verify NO DhanHQ logic moved to prompts
- [ ] Verify LLM never sees raw OHLC/option chains
- [ ] Verify agent progresses fast
- [ ] Verify NO_TRADE support

---

**END OF MANDATE**
