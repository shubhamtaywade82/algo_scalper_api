---
name: remove_duplication
description: Identify and eliminate duplicate code through extraction, parameterisation, and abstraction
tags: [refactoring, dry, duplication, abstraction]
applies_to: [all]
severity: major
---

## Goal

**DRY — Don't Repeat Yourself.** Every piece of knowledge should have a single,
authoritative representation in the system. Duplication means two places to
update when requirements change, and two places for bugs to hide.

## Types of Duplication

### 1. Exact duplication — copy-paste

Identical blocks in two locations. Fix: extract to shared method.

### 2. Near duplication — minor variation

Same structure, one or two values differ. Fix: extract and parameterise.

### 3. Conceptual duplication — same idea, different code

Two implementations of the same business rule. Fix: extract to a
canonical policy/service.

### 4. Knowledge duplication — implicit structure

The same magic number or rule (e.g., "ADX > 25 means trending") appears
in 5 different files as `adx > 25`. Fix: extract to a named constant or method.

## Detection Rules

Flag when:
- Identical 3+ line block appears in 2+ methods or files
- Same conditional structure repeated with minor variable differences
- Same magic number/string in 3+ places
- A method chain `x.to_s.downcase.to_sym` appears 4+ times without a helper
- Business rule (e.g., "position is stale after 30 minutes") is defined in
  2+ places

## Refactoring Strategies

### Strategy 1: Extract to shared private method

```ruby
# Duplicated in 3 methods
adx_result = instrument.adx(14)&.to_f || 0.0
rsi_result = instrument.rsi(14)&.to_f || 0.0

# Extract once
def indicator_values(instrument)
  { adx: instrument.adx(14).to_f, rsi: instrument.rsi(14).to_f }
end
```

### Strategy 2: Parameterise the variation

```ruby
# Duplicated — only the field name differs
def nifty_instruments
  Instrument.where(symbol_name: 'NIFTY').active
end

def sensex_instruments
  Instrument.where(symbol_name: 'SENSEX').active
end

# Parameterise
def instruments_for(index_key)
  Instrument.where(symbol_name: index_key.upcase).active
end
```

### Strategy 3: Extract to a concern or module

```ruby
# Same logging pattern in 5 services
Rails.logger.info("[#{self.class.name}] #{message}")

# Extract to module
module ServiceLogging
  def log(message, level: :info)
    Rails.logger.public_send(level, "[#{self.class.name}] #{message}")
  end
end
```

### Strategy 4: Configuration-driven elimination

```ruby
# Duplicated guard logic in 5 entry guards
return unless AlgoConfig.fetch.dig(:risk, :circuit_breaker_clear)
return unless AlgoConfig.fetch.dig(:risk, :within_daily_loss_limit)
return unless AlgoConfig.fetch.dig(:risk, :cooldown_expired)

# Extract to a policy object
class Policies::EntryPermissionPolicy
  def permitted?
    circuit_breaker_clear? && within_daily_loss_limit? && cooldown_expired?
  end
end
```

## Trading System Duplication Hotspots

Check for duplication in:
- ADX/RSI threshold checks across signal files → `TrendStrengthPolicy`
- Strike selection logic across different index rule files → parameterised base
- Option type normalisation (`side.to_s.downcase.to_sym`) → helper method or VO
- Expiry date parsing across chain analyzer and derivative analyzer → `ExpiryParser`
- Meta hash merge patterns in exit enforcement → `MetaUpdater` or model method

## Agent Instructions

1. Scan for blocks of 3+ lines that appear more than once.
2. For near-duplication, identify the varying parts and propose parameterisation.
3. For conceptual duplication, identify the canonical home for the rule.
4. Show the extracted version and all call sites updated.
5. Count how many places the duplication is removed from — the higher the
   count, the higher the priority.
