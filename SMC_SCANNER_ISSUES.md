# SMC Scanner Run Issues Analysis

**Date**: 2025-01-13
**Command**: `bundle exec rake 'smc:scan[NIFTY]'`
**Status**: ⚠️ **ISSUES FOUND**

## Executive Summary

The SMC scanner completed successfully but revealed several issues in the AI analyzer component that cause inefficient tool usage and wasted iterations. The AI repeatedly calls the same tool with invalid parameters, wasting 6 out of 10 maximum iterations.

## Issues Found

### 🔴 CRITICAL: AI Tool Loop - Repeated Tool Calls with Invalid Parameters

**Issue**: The AI analyzer repeatedly calls `get_option_chain` with an empty `expiry_date` parameter (`{"expiry_date":""}`) from iterations 4-10, even after receiving valid option chain data.

**Evidence from Logs**:
```
[Smc::AiAnalyzer] Iteration 4/10
[Smc::AiAnalyzer] Tool calls detected: get_option_chain
[Smc::AiAnalyzer] Executing tool: get_option_chain with args: {"expiry_date"=>""}
[Smc::AiAnalyzer] Invalid expiry date format: , using nearest expiry
[Smc::AiAnalyzer] Using nearest expiry from instrument: 2026-01-13 (5 days away) for NIFTY
[Smc::AiAnalyzer] Loading option chain for NIFTY expiry 2026-01-13 with spot 26140.75
```

This pattern repeats for iterations 5, 6, 7, 8, 9, and 10.

**Impact**:
- Wastes 6 iterations (60% of max iterations) calling the same tool
- Increases API costs (each tool call = 1 API request)
- Delays final analysis response
- Forces premature termination at iteration 9/10

**Root Cause**:
1. The AI doesn't recognize it already has option chain data from previous successful calls
2. The tool detection logic (`has_option_chain`) checks for tool calls but the AI ignores the prompt to stop
3. The prompt at line 481 (`has_option_chain && has_ltp && iteration >= 3`) should stop it at iteration 4, but the AI continues calling tools

**Location**: `app/services/smc/ai_analyzer.rb:447-492`

---

### 🟡 MEDIUM: Empty Expiry Date Parameter Handling

**Issue**: The AI consistently passes `expiry_date: ""` (empty string) to `get_option_chain`, triggering a warning but the tool still works.

**Evidence**:
```
[Smc::AiAnalyzer] Invalid expiry date format: , using nearest expiry
```

**Impact**:
- Unnecessary warnings in logs
- Indicates AI doesn't understand the tool parameter requirements
- Tool description says "Do NOT provide expiry_date unless you are certain" but AI provides empty string anyway

**Root Cause**:
- Tool description at line 656 says to leave `expiry_date` empty, but the AI is passing an empty string `""` instead of omitting the parameter
- The tool handles this gracefully but logs a warning

**Location**: `app/services/smc/ai_analyzer.rb:655-660` (tool definition), `app/services/smc/ai_analyzer.rb:992-994` (handling)

---

### 🟡 MEDIUM: Tool Call Detection Not Effective

**Issue**: The code detects that `has_option_chain` is true (line 448-450), but the AI still continues calling tools despite prompts to stop.

**Evidence**:
- `has_option_chain` check passes (tool was called in iteration 4)
- Prompt at line 481 should trigger at iteration 4+ when `has_option_chain && has_ltp && iteration >= 3`
- But AI continues calling `get_option_chain` in iterations 5-10

**Impact**:
- Detection logic exists but doesn't prevent the loop
- Prompts to stop are ignored by the AI

**Root Cause**:
- The prompt might not be strong enough
- The AI might not be recognizing the tool response format
- The check happens after tool execution, so the AI has already decided to call the tool

**Location**: `app/services/smc/ai_analyzer.rb:447-492`

---

### 🟡 MEDIUM: Consecutive Errors Logic May Be Flawed

**Issue**: The `consecutive_errors` counter logic increments for "empty results" (line 414-418), but the option chain is actually being loaded successfully.

**Evidence**:
- Tool returns valid option chain data (no error)
- But `consecutive_errors` might be incremented incorrectly
- At iteration 9, it triggers: "Too many consecutive errors (0) or near max iterations (9)"

**Impact**:
- Logic confusion - errors counter shows 0 but still triggers force-stop
- May mask actual error conditions

**Location**: `app/services/smc/ai_analyzer.rb:394-424`

---

### 🟢 LOW: Inefficient Iteration Usage

**Issue**: The AI wastes 60% of available iterations (6 out of 10) on redundant tool calls.

**Impact**:
- Reduces available iterations for actual analysis
- Forces premature termination
- Could cause incomplete analysis if more tools were needed

**Mitigation**: The force-stop logic at iteration 9 prevents infinite loops, but wastes iterations.

---

## Recommendations

### Priority 1: Fix AI Tool Loop

1. **Improve Tool Call Detection**:
   - Check for successful tool results, not just tool calls
   - Verify option chain data is actually present in messages
   - Add explicit check: "If option chain data exists in tool results, DO NOT call get_option_chain again"

2. **Strengthen Stop Prompts**:
   - Make prompts more explicit: "You have already received option chain data in tool response [X]. DO NOT call get_option_chain again."
   - Add tool result summaries to prompts
   - Use stronger language earlier (iteration 2-3 instead of 4-5)

3. **Add Tool Call Deduplication**:
   - Track which tools have been called successfully
   - Prevent calling the same tool with the same parameters multiple times
   - Add to `failed_tools` tracking logic

### Priority 2: Fix Empty Expiry Date Parameter

1. **Update Tool Description**:
   - Clarify: "Leave expiry_date parameter completely omitted (not empty string) if unsure"
   - Or: "If expiry_date is empty string, it will be ignored and nearest expiry used"

2. **Normalize Empty Strings**:
   - In `execute_tool`, convert empty string `""` to `nil` for `expiry_date`
   - This prevents the warning and makes intent clearer

### Priority 3: Improve Error Tracking

1. **Fix Consecutive Errors Logic**:
   - Only increment `consecutive_errors` for actual errors, not empty results
   - Empty option chain should be treated differently than errors
   - Add separate counter for "redundant tool calls"

2. **Better Logging**:
   - Log when tool is called with same parameters as previous successful call
   - Log when `has_option_chain` is true but AI still calls the tool

---

## Code Locations

- **Main Loop**: `app/services/smc/ai_analyzer.rb:222-512` (`execute_conversation`)
- **Tool Detection**: `app/services/smc/ai_analyzer.rb:447-455`
- **Prompt Logic**: `app/services/smc/ai_analyzer.rb:457-492`
- **Tool Execution**: `app/services/smc/ai_analyzer.rb:363-445`
- **Error Tracking**: `app/services/smc/ai_analyzer.rb:394-424`
- **Option Chain Tool**: `app/services/smc/ai_analyzer.rb:926-1086` (`get_option_chain`)

---

## Test Case

To reproduce:
```bash
bundle exec rake 'smc:scan[NIFTY]'
```

Expected: AI should call `get_option_chain` once, receive data, and provide analysis.

Actual: AI calls `get_option_chain` 7 times (iterations 4-10) with same empty parameter.

---

## Status

✅ **Scanner Completes**: The rake task completes successfully
⚠️ **Inefficient**: Wastes iterations on redundant tool calls
⚠️ **Warnings**: Logs show repeated "Invalid expiry date format" warnings
✅ **Final Analysis**: Eventually provides trading recommendation after force-stop

