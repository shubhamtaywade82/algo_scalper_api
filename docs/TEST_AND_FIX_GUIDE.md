# Test and Fix Guide - Technical Analysis Agent

This guide explains how to test the refactored agent, monitor for issues, and fix errors iteratively.

## Quick Start

### 1. Run Comprehensive Test Suite

```bash
# Run all tests
rails runner scripts/test_agent.rb

# Or run specific test
rails runner scripts/test_agent.rb intent
rails runner scripts/test_agent.rb context
rails runner scripts/test_agent.rb decision
rails runner scripts/test_agent.rb tools
rails runner scripts/test_agent.rb full "Analyse NIFTY for options buying"
```

### 2. Interactive Monitoring

```bash
# Start interactive monitor
rails runner scripts/monitor_agent.rb

# Or test specific query
rails runner scripts/monitor_agent.rb "What is the price of NIFTY?"
rails runner scripts/monitor_agent.rb "Analyse RELIANCE for swing trading" --stream
```

## Test Workflow

### Step 1: Test Individual Components

Start by testing each component in isolation:

```bash
# Test Intent Resolver
rails runner scripts/test_agent.rb intent

# Test Agent Context
rails runner scripts/test_agent.rb context

# Test Decision Engine
rails runner scripts/test_agent.rb decision

# Test Wrapper Tools
rails runner scripts/test_agent.rb tools
```

**What to look for:**
- ✅ No exceptions
- ✅ Correct intent extraction
- ✅ Proper instrument resolution
- ✅ Valid tool decisions

### Step 2: Test Full Agent Loop

Test the complete agent with simple queries first:

```bash
# Simple price query
rails runner scripts/test_agent.rb full "What is the price of NIFTY?"

# Swing trading
rails runner scripts/test_agent.rb full "Analyse RELIANCE for swing trading"

# Options buying
rails runner scripts/test_agent.rb full "Analyse NIFTY for options buying"
```

**What to look for:**
- ✅ Verdict: `ANALYSIS_COMPLETE` or `NO_TRADE` (not `ERROR`)
- ✅ Reasonable iteration count (< 10)
- ✅ No exceptions in output
- ✅ Valid analysis result

### Step 3: Monitor Real Queries

Use the interactive monitor to test real-world queries:

```bash
rails runner scripts/monitor_agent.rb
```

Then enter queries interactively:
```
Query> What is the price of TCS?
Query> Analyse BANKNIFTY for options buying
Query> summary
Query> exit
```

## Common Issues and Fixes

### Issue 1: "uninitialized constant AgentContext"

**Error:**
```
NameError: uninitialized constant Services::Ai::TechnicalAnalysisAgent::AgentContext
```

**Fix:**
- Check that `agent_context.rb` is loaded in `technical_analysis_agent.rb`
- Verify the file path: `lib/services/ai/technical_analysis_agent/agent_context.rb`
- Restart Rails console/server

**Verify:**
```ruby
# In Rails console
require_relative 'lib/services/ai/technical_analysis_agent/agent_context'
Services::Ai::TechnicalAnalysisAgent::AgentContext.new({})
```

### Issue 2: "undefined method `resolve_instrument_deterministically`"

**Error:**
```
NoMethodError: undefined method `resolve_instrument_deterministically`
```

**Fix:**
- Check that `DecisionEngine` module is included in `TechnicalAnalysisAgent`
- Verify the method exists in `decision_engine.rb`
- Check module inclusion order

**Verify:**
```ruby
# In Rails console
agent = Services::Ai::TechnicalAnalysisAgent.new
agent.methods.grep(/resolve_instrument/)
```

### Issue 3: "Intent resolution returns nil"

**Error:**
- Intent resolver returns `nil` or empty hash
- Low confidence scores

**Fix:**
- Check that OpenAI/Ollama client is enabled
- Verify API credentials
- Check LLM response format

**Debug:**
```ruby
# In Rails console
agent = Services::Ai::TechnicalAnalysisAgent.new
result = agent.resolve_intent("Analyse NIFTY for options buying")
puts result.inspect
```

### Issue 4: "Agent loop stalls or times out"

**Error:**
- Agent reaches max iterations
- No analysis returned
- Infinite loop

**Fix:**
- Check `AI_AGENT_MAX_ITERATIONS` (default: 15)
- Verify DecisionEngine is returning valid tools
- Check for repeating tool calls

**Debug:**
```ruby
# Enable verbose logging
ENV['RAILS_LOG_LEVEL'] = 'debug'
rails runner scripts/monitor_agent.rb "Analyse NIFTY"
```

### Issue 5: "Tool execution fails"

**Error:**
- `tool_resolve_instrument` returns error
- `tool_get_ltp` fails
- Instrument not found

**Fix:**
- Verify instruments exist in database
- Check DhanHQ error handler is loaded
- Verify instrument segments/exchanges

**Debug:**
```ruby
# In Rails console
# Check if instrument exists
Instrument.where(underlying_symbol: 'NIFTY').first

# Test tool directly
agent = Services::Ai::TechnicalAnalysisAgent.new
result = agent.tool_resolve_instrument({ 'symbol' => 'NIFTY' })
puts result.inspect
```

### Issue 6: "Option chain not filtered"

**Error:**
- Full option chain passed to LLM
- Too many strikes in result

**Fix:**
- Check `tool_fetch_option_chain` wrapper
- Verify `narrow_option_chain` in DecisionEngine
- Check ATM calculation logic

**Debug:**
```ruby
# In Rails console
agent = Services::Ai::TechnicalAnalysisAgent.new
result = agent.tool_fetch_option_chain({ 'instrument_id' => 1 })
puts "Strikes count: #{result[:strikes]&.length}"
puts "Should be <= 5"
```

## Debugging Tips

### 1. Enable Verbose Logging

```ruby
# In Rails console or script
Rails.logger.level = Logger::DEBUG
ENV['RAILS_LOG_LEVEL'] = 'debug'
```

### 2. Test Individual Methods

```ruby
# In Rails console
agent = Services::Ai::TechnicalAnalysisAgent.new

# Test intent resolver
intent = agent.resolve_intent("Analyse NIFTY for options buying")
puts intent.inspect

# Test context creation
context = Services::Ai::TechnicalAnalysisAgent::AgentContext.new(intent)
puts context.inspect

# Test decision engine
next_tool = agent.next_tool(context)
puts next_tool.inspect
```

### 3. Check Module Inclusion

```ruby
# In Rails console
agent = Services::Ai::TechnicalAnalysisAgent.new
puts agent.class.included_modules

# Should include:
# - IntentResolver
# - DecisionEngine
# - AdaptiveController
# - AgentRunner
```

### 4. Monitor Agent Loop Step-by-Step

Add debug output in `agent_runner.rb`:

```ruby
# In agent_runner.rb, add:
Rails.logger.debug("[AgentRunner] Iteration #{iteration}: #{next_tool.inspect}")
Rails.logger.debug("[AgentRunner] Context ready: #{context.ready_for_analysis?}")
```

### 5. Test with Mock Data

```ruby
# In Rails console
# Create mock context
context = Services::Ai::TechnicalAnalysisAgent::AgentContext.new({
  intent: :options_buying,
  underlying_symbol: 'NIFTY',
  confidence: 0.9
})

# Manually set resolved instrument
context.resolved_instrument = Instrument.where(underlying_symbol: 'NIFTY').first
context.ltp = 24500.0

# Test decision engine
agent = Services::Ai::TechnicalAnalysisAgent.new
next_tool = agent.next_tool(context)
puts next_tool.inspect
```

## Fixing Issues Iteratively

### Workflow

1. **Run test** → Identify error
2. **Isolate component** → Test individual method
3. **Fix issue** → Update code
4. **Re-test** → Verify fix
5. **Repeat** → Until all tests pass

### Example Fix Session

```bash
# 1. Run test
rails runner scripts/test_agent.rb full "Analyse NIFTY"

# 2. See error: "undefined method `resolve_instrument_deterministically`"

# 3. Check if method exists
rails runner -e "agent = Services::Ai::TechnicalAnalysisAgent.new; puts agent.methods.grep(/resolve/)"

# 4. Fix: Add method to DecisionEngine or include module

# 5. Re-test
rails runner scripts/test_agent.rb decision

# 6. Test full loop again
rails runner scripts/test_agent.rb full "Analyse NIFTY"
```

## Environment Variables

Control agent behavior:

```bash
# Enable/disable agent runner
export AI_USE_AGENT_RUNNER=true

# Limit iterations
export AI_AGENT_MAX_ITERATIONS=10

# Payload size limit
export AI_MAX_PAYLOAD_SIZE=2000

# Run with settings
AI_USE_AGENT_RUNNER=true AI_AGENT_MAX_ITERATIONS=5 rails runner scripts/test_agent.rb
```

## Success Criteria

✅ All component tests pass
✅ Full agent loop completes without errors
✅ Verdict is `ANALYSIS_COMPLETE` or `NO_TRADE` (not `ERROR`)
✅ Iteration count is reasonable (< 10 for simple queries)
✅ No exceptions in logs
✅ Analysis result is valid

## Next Steps

After fixing all issues:

1. Run full test suite: `rails runner scripts/test_agent.rb`
2. Test with various query types
3. Monitor performance
4. Tune decision engine rules if needed
5. Add more test cases

---

**Remember:** Fix one issue at a time, test after each fix, and keep iterating until all tests pass.
