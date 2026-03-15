---
name: extract_method
description: Systematic process for safely extracting methods from long or complex blocks
tags: [refactoring, extract_method, methods]
applies_to: [all]
severity: info
---

## Goal

Extract cohesive code blocks into well-named private methods, reducing the
original method's size and making the extracted logic independently testable.

## When to Extract

Extract a method when:
- A comment describes a block of code (the comment is the method name)
- A block of code can be given a clear domain name
- The same block appears more than once
- The block is testable as a standalone unit
- The block is at a different abstraction level from the surrounding code

## The Extract Method Process

### Step 1: Identify the block to extract

Look for natural cohesion — lines that work together toward one sub-goal.

```ruby
def run_cycle
  # ==== Step 1: fetch indicators ====        ← natural extraction boundary
  adx_result = instrument.adx(14)
  rsi_value  = instrument.rsi(14)
  st_result  = instrument.supertrend_signal

  # ==== Step 2: evaluate regime ====         ← natural extraction boundary
  regime = if adx_result.to_f > 25
             rsi_value < 70 ? 'TRENDING_UP' : 'RANGING'
           else
             'CHOPPY'
           end
  ...
end
```

### Step 2: Identify inputs and output

- **Inputs:** variables read from outer scope → become parameters
- **Output:** the value the block produces → return value
- **Side effects:** if the block mutates shared state, note it

### Step 3: Extract and name

```ruby
def run_cycle
  indicators = fetch_indicators
  regime     = evaluate_regime(indicators)
  ...
end

private

def fetch_indicators
  {
    adx: instrument.adx(14),
    rsi: instrument.rsi(14),
    supertrend: instrument.supertrend_signal
  }
end

def evaluate_regime(indicators)
  return 'TRENDING_UP'   if strong_trend?(indicators) && rsi_ok?(indicators)
  return 'TRENDING_DOWN' if strong_downtrend?(indicators)
  return 'RANGING'       if adx_weak?(indicators)
  'CHOPPY'
end
```

### Step 4: Verify

- Original method reads as a clear story
- Extracted method has no implicit dependencies on surrounding state
- Existing tests still pass
- Extracted method can be tested in isolation

## Naming the Extracted Method

Use the comment (if present) as the basis for the name:
- `# calculate position size` → `calculate_position_size`
- `# check if signal is valid` → `valid_signal?`
- `# build instrument hash for API` → `build_instrument_params`

## Anti-patterns to Avoid

### Over-extraction

Don't extract trivially — every extraction adds a method invocation and a name
to look up. A 2-line block that's only used once is not worth extracting unless
the name adds significant clarity.

### Extracting with too many parameters

If the extracted method needs 5+ parameters, consider whether the extraction
boundary is wrong — or whether a Value Object would help.

```ruby
# Bad extraction — parameter list explosion
def evaluate_regime(adx, rsi, ema, volume, spread, regime_cfg)

# Better — pass a value object
def evaluate_regime(indicators)  # indicators is a hash or VO
```

## Agent Instructions

When suggesting an extract method refactoring:

1. Show the before (original method with highlighted block).
2. Show the after (original method + new extracted method).
3. Name the extracted method using domain vocabulary from the file.
4. Note any parameters needed and what the return type/shape will be.
5. Flag if the extracted method would need its own tests.
