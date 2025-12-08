# Signal::Scheduler - Detailed Explanation & Recommendations

## 📋 Table of Contents
1. [Overview](#overview)
2. [Architecture & Flow](#architecture--flow)
3. [Signal Evaluation Paths](#signal-evaluation-paths)
4. [Dependencies & Integration](#dependencies--integration)
5. [Critical Issues](#critical-issues)
6. [Recommendations](#recommendations)

---

## Overview

**Service:** `Signal::Scheduler`  
**Location:** `app/services/signal/scheduler.rb`  
**Purpose:** Periodically analyzes market data and generates trading signals for configured indices  
**Frequency:** Every 30 seconds (configurable via `DEFAULT_PERIOD`)  
**Thread:** `'signal-scheduler'` (background thread)

### Key Responsibilities
1. **Market Analysis**: Evaluates technical indicators (Supertrend, ADX, TrendScorer)
2. **Signal Generation**: Determines bullish/bearish direction for each index
3. **Strike Selection**: Selects optimal option strikes via `Options::ChainAnalyzer`
4. **Entry Triggering**: Calls `Entries::EntryGuard.try_enter()` to place orders

---

## Architecture & Flow

### Startup Sequence

```ruby
# 1. Initialization (via TradingSystem::Supervisor)
Signal::Scheduler.new(period: 30)

# 2. Start method creates background thread
def start
  @running = true
  @thread = Thread.new do
    Thread.current.name = 'signal-scheduler'
    loop do
      # Process each index
      indices.each_with_index do |idx_cfg, idx|
        sleep(idx.zero? ? 0 : 5)  # 5s delay between indices
        process_index(idx_cfg)
      end
      sleep @period  # 30s delay before next cycle
    end
  end
end
```

### Main Processing Loop

```
┌─────────────────────────────────────────────────────────┐
│  Signal::Scheduler Thread (every 30 seconds)           │
└─────────────────────────────────────────────────────────┘
                        │
                        ▼
        ┌───────────────────────────────┐
        │  Loop through indices         │
        │  (NIFTY, BANKNIFTY, SENSEX)  │
        └───────────────────────────────┘
                        │
                        ▼
        ┌───────────────────────────────┐
        │  Check market closed?         │
        │  (Skip if after 3:30 PM IST)  │
        └───────────────────────────────┘
                        │
                        ▼
        ┌───────────────────────────────┐
        │  evaluate_supertrend_signal() │
        └───────────────────────────────┘
                        │
        ┌───────────────┴───────────────┐
        │                               │
        ▼                               ▼
┌───────────────┐             ┌───────────────┐
│ TrendScorer  │             │ Legacy Engine │
│ Path (NEW)   │             │ Path (OLD)    │
└───────────────┘             └───────────────┘
        │                               │
        └───────────────┬───────────────┘
                        │
                        ▼
        ┌───────────────────────────────┐
        │  select_candidate_from_chain() │
        │  (Options::ChainAnalyzer)      │
        └───────────────────────────────┘
                        │
                        ▼
        ┌───────────────────────────────┐
        │  process_signal()              │
        │  build_pick_from_signal()      │
        └───────────────────────────────┘
                        │
                        ▼
        ┌───────────────────────────────┐
        │  Entries::EntryGuard.try_enter()│
        │  (Places order)                │
        └───────────────────────────────┘
```

---

## Signal Evaluation Paths

### Path 1: TrendScorer (Direction-First) - **NEW**

**Enabled when:** `feature_flags[:enable_trend_scorer] == true` OR `feature_flags[:enable_direction_before_chain] == true`

**⚠️ NOTE:** Currently uses hardcoded indicators. A modular indicators system with confluence (composite indicators) is **planned but not implemented** (see `docs/SIGNAL_GENERATION_MODULARIZATION.md`).

**Flow:**
```ruby
# Step 1: Compute trend score (0-21)
trend_result = Signal::TrendScorer.compute_direction(
  index_cfg: index_cfg,
  primary_tf: '1m',
  confirmation_tf: '5m',
  bullish_threshold: 14.0,
  bearish_threshold: 7.0
)

# Step 2: Check minimum trend score
min_trend_score = signal_config.dig(:trend_scorer, :min_trend_score) || 14.0
if trend_score < min_trend_score || direction.nil?
  return nil  # Skip signal
end

# Step 3: Select candidate from chain
candidate = select_candidate_from_chain(
  index_cfg: index_cfg,
  direction: direction,
  chain_cfg: chain_cfg,
  trend_score: trend_score
)

# Step 4: Build signal hash
{
  segment: candidate[:segment],
  security_id: candidate[:security_id],
  reason: 'trend_scorer_direction',
  meta: {
    candidate_symbol: candidate[:symbol],
    lot_size: candidate[:lot_size],
    direction: direction,
    trend_score: trend_score,
    source: 'trend_scorer',
    multiplier: 1
  }
}
```

**TrendScorer Components:**
- **PA_score (0-7)**: Price action patterns, momentum, structure breaks
- **IND_score (0-7)**: Technical indicators (RSI, MACD, ADX, Supertrend)
- **MTF_score (0-7)**: Multi-timeframe alignment (1m vs 5m)

**Total Score Range:** 0-21
- **≥ 14.0**: Bullish signal
- **≤ 7.0**: Bearish signal
- **7.0 - 14.0**: No signal (neutral)

### Path 2: Legacy Engine (Supertrend + ADX) - **OLD**

**Enabled when:** TrendScorer is disabled

**Flow:**
```ruby
# Step 1: Multi-timeframe analysis
indicator_result = Signal::Engine.analyze_multi_timeframe(
  index_cfg: index_cfg,
  instrument: instrument
)

# Step 2: Check direction
direction = indicator_result[:final_direction]
if direction.nil? || direction == :avoid
  return nil  # Skip signal
end

# Step 3: Select candidate from chain
trend_metric = indicator_result.dig(:timeframe_results, :primary, :adx_value)
candidate = select_candidate_from_chain(
  index_cfg: index_cfg,
  direction: direction,
  chain_cfg: chain_cfg,
  trend_score: trend_metric
)

# Step 4: Build signal hash
{
  segment: candidate[:segment],
  security_id: candidate[:security_id],
  reason: 'supertrend_adx',
  meta: {
    candidate_symbol: candidate[:symbol],
    lot_size: candidate[:lot_size],
    direction: direction,
    trend_score: trend_metric,
    source: 'supertrend_adx',
    multiplier: 1
  }
}
```

**Legacy Engine Components:**
- **Supertrend**: Trend direction indicator
- **ADX**: Trend strength indicator (min_strength configurable)
- **Multi-timeframe**: Primary (1m/5m) + Confirmation (5m/15m) alignment

---

## Dependencies & Integration

### Required Services

1. **MarketFeedHub** ✅
   - Provides LTP data via `Live::TickCache.ltp()`
   - Used indirectly by `Options::ChainAnalyzer` for strike selection

2. **IndexInstrumentCache** ✅
   - Caches index instruments (NIFTY, BANKNIFTY, SENSEX)
   - Used to fetch instrument for analysis

3. **Options::ChainAnalyzer** ✅
   - Selects option strikes based on direction
   - Filters by ATM, OI, IV, spread
   - Returns top candidates

4. **Entries::EntryGuard** ✅
   - Validates entry conditions
   - Places orders (live) or creates paper trackers
   - Enforces daily limits, exposure, cooldown

### Data Flow

```
MarketFeedHub (WebSocket)
    ↓
TickCache.ltp()  ← Reads LTP for strike selection
    ↓
Signal::Scheduler
    ↓
IndexInstrumentCache.get_or_fetch()  ← Gets index instrument
    ↓
TrendScorer.compute_direction() OR Signal::Engine.analyze_multi_timeframe()
    ↓
Options::ChainAnalyzer.select_candidates()  ← Selects strikes
    ↓
Entries::EntryGuard.try_enter()  ← Places order
```

---

## Critical Issues

### 🔴 **CRITICAL: V3 Modules Not Integrated**

**Current Flow:**
```ruby
Signal::Scheduler
  → process_signal()
    → Entries::EntryGuard.try_enter()  # DIRECT CALL - BYPASSES V3 MODULES
```

**Expected Flow (V3 Architecture):**
```ruby
Signal::Scheduler
  → Signal::IndexSelector.select_best_index()  # ❌ NOT CALLED
    → Signal::TrendScorer.compute_direction()  # ✅ CALLED (but standalone)
  → Options::StrikeSelector.select()  # ❌ NOT CALLED
    → Options::PremiumFilter.valid?()  # ❌ NOT CALLED
  → Orders::EntryManager.process_entry()  # ❌ NOT CALLED
    → Capital::DynamicRiskAllocator.risk_pct_for()  # ❌ NOT CALLED
    → Entries::EntryGuard.try_enter()  # ✅ CALLED (but directly)
    → Positions::ActiveCache.add()  # ❌ NOT CALLED
    → Orders::BracketPlacer.place_bracket()  # ❌ NOT CALLED
```

**Impact:**
- ❌ V3 modules (`IndexSelector`, `StrikeSelector`, `EntryManager`) are **orphaned**
- ❌ Dynamic risk allocation is **not used**
- ❌ Premium filtering is **not applied**
- ❌ ActiveCache insertion is **skipped**
- ❌ Bracket order placement is **not integrated**

**Location:** `app/services/signal/scheduler.rb:96-101`

---

## Recommendations

### 1. 🔴 **HIGH PRIORITY: Integrate V3 Modules**

**Problem:** Signal::Scheduler bypasses all V3 modules and calls EntryGuard directly.

**Solution:** Replace direct `EntryGuard.try_enter()` call with `EntryManager.process_entry()`:

```ruby
# Current (app/services/signal/scheduler.rb:90-108)
def process_signal(index_cfg, signal)
  pick = build_pick_from_signal(signal)
  direction = signal.dig(:meta, :direction)&.to_sym || determine_direction(index_cfg)
  multiplier = signal[:meta][:multiplier] || 1

  result = Entries::EntryGuard.try_enter(  # ❌ DIRECT CALL
    index_cfg: index_cfg,
    pick: pick,
    direction: direction,
    scale_multiplier: multiplier
  )
  # ...
end

# Recommended
def process_signal(index_cfg, signal)
  pick = build_pick_from_signal(signal)
  direction = signal.dig(:meta, :direction)&.to_sym || determine_direction(index_cfg)
  trend_score = signal.dig(:meta, :trend_score) || 0

  # Use EntryManager (V3 architecture)
  result = Orders::EntryManager.process_entry(
    index_cfg: index_cfg,
    pick: pick,
    direction: direction,
    trend_score: trend_score,
    source: signal.dig(:meta, :source) || 'signal_scheduler'
  )

  unless result[:success]
    Rails.logger.warn(
      "[Scheduler] EntryManager rejected signal for #{index_cfg[:key]}: " \
      "#{signal[:meta][:candidate_symbol]} - #{result[:reason]}"
    )
  end
end
```

**Benefits:**
- ✅ Enables dynamic risk allocation
- ✅ Applies premium filtering
- ✅ Adds positions to ActiveCache
- ✅ Integrates bracket order placement
- ✅ Uses StrikeSelector for better strike selection

---

### 2. 🟡 **MEDIUM PRIORITY: Add Signal Deduplication**

**Problem:** Scheduler may generate duplicate signals within short timeframes.

**Solution:** Add cooldown/deduplication logic:

```ruby
class Signal::Scheduler
  def initialize(period: DEFAULT_PERIOD, data_provider: nil)
    # ...
    @last_signal_at = {}  # { index_key => Time }
    @signal_cooldown = 300  # 5 minutes
  end

  def process_signal(index_cfg, signal)
    index_key = index_cfg[:key]
    
    # Check cooldown
    if @last_signal_at[index_key] && 
       (Time.current - @last_signal_at[index_key]) < @signal_cooldown
      Rails.logger.debug(
        "[Scheduler] Skipping duplicate signal for #{index_key} " \
        "(cooldown active: #{@signal_cooldown}s)"
      )
      return
    end

    # Process signal...
    result = Entries::EntryGuard.try_enter(...)
    
    # Update last signal time on success
    @last_signal_at[index_key] = Time.current if result
  end
end
```

---

### 3. 🟡 **MEDIUM PRIORITY: Improve Error Handling**

**Problem:** Chain analysis failures are logged but not retried.

**Solution:** Add retry logic with exponential backoff:

```ruby
def select_candidate_from_chain(index_cfg, direction, chain_cfg, trend_score)
  retries = 3
  attempt = 0
  
  begin
    analyzer = Options::ChainAnalyzer.new(
      index: index_cfg,
      data_provider: @data_provider,
      config: chain_cfg
    )
    
    limit = (chain_cfg[:max_candidates] || 3).to_i
    candidates = analyzer.select_candidates(limit: limit, direction: direction)
    
    return nil if candidates.blank?
    
    candidate = candidates.first.dup
    candidate[:trend_score] ||= trend_score
    candidate
  rescue StandardError => e
    attempt += 1
    if attempt < retries
      sleep(2 ** attempt)  # Exponential backoff: 2s, 4s, 8s
      retry
    else
      Rails.logger.error(
        "[SignalScheduler] Chain analyzer failed after #{retries} attempts: " \
        "#{e.class} - #{e.message}"
      )
      nil
    end
  end
end
```

---

### 4. 🟢 **LOW PRIORITY: Add Performance Monitoring**

**Problem:** No metrics for scheduler performance or signal generation rate.

**Solution:** Add instrumentation:

```ruby
def process_index(index_cfg)
  start_time = Time.current
  
  return if TradingSession::Service.market_closed?
  
  signal = evaluate_supertrend_signal(index_cfg)
  return unless signal
  
  process_signal(index_cfg, signal)
  
  duration = (Time.current - start_time) * 1000  # milliseconds
  Rails.logger.info(
    "[SignalScheduler] Processed #{index_cfg[:key]} in #{duration.round(1)}ms"
  )
  
  # Emit metrics (if using StatsD/DataDog)
  # StatsD.timing('signal_scheduler.process_index.duration', duration)
  # StatsD.increment('signal_scheduler.signals.generated') if signal
rescue StandardError => e
  Rails.logger.error(
    "[SignalScheduler] process_index error #{index_cfg[:key]}: " \
    "#{e.class} - #{e.message}"
  )
  # StatsD.increment('signal_scheduler.errors')
end
```

---

### 5. 🔴 **HIGH PRIORITY: Implement Modular Indicators System with Confluence**

**Problem:** Indicators are hardcoded in `TrendScorer`. A modular system with confluence (composite indicators) is documented but not implemented.

**Planned Architecture** (from `docs/SIGNAL_GENERATION_MODULARIZATION.md`):
- `Indicators::Registry` - Singleton registry for managing indicators
- `Indicators::Composite` - Combines multiple indicators with confluence modes:
  - `weighted_sum`: Weighted average of indicator scores
  - `majority_vote`: Majority direction wins
  - `all_must_agree`: All indicators must agree
  - `any_one`: Any indicator can trigger signal
- Individual indicator classes: `Indicators::Rsi`, `Indicators::Macd`, `Indicators::Adx`, `Indicators::SupertrendIndicator`, `Indicators::PriceAction`

**Benefits:**
- ✅ Enable/disable indicators via config (no code changes)
- ✅ Configurable indicator weights/parameters per index
- ✅ Multiple confluence modes for combining indicators
- ✅ Easy to add new indicators without modifying core code

**Implementation Status:** ❌ **NOT IMPLEMENTED** (documented only)

**Recommendation:** Implement Phase 1-2 from `docs/SIGNAL_MODULARIZATION_SUMMARY.md`:
1. Create `Indicators::Base` interface
2. Create `Indicators::Registry` singleton
3. Create `Indicators::Composite` class with confluence modes
4. Extract individual indicators from `TrendScorer`

---

### 6. 🟢 **LOW PRIORITY: Add Signal Validation**

**Problem:** No validation of signal quality before processing.

**Solution:** Add validation layer:

```ruby
def process_signal(index_cfg, signal)
  # Validate signal structure
  unless signal_valid?(signal)
    Rails.logger.warn(
      "[Scheduler] Invalid signal structure for #{index_cfg[:key]}: #{signal.inspect}"
    )
    return
  end
  
  # Validate pick data
  pick = build_pick_from_signal(signal)
  unless pick_valid?(pick)
    Rails.logger.warn(
      "[Scheduler] Invalid pick data for #{index_cfg[:key]}: #{pick.inspect}"
    )
    return
  end
  
  # Process signal...
end

private

def signal_valid?(signal)
  signal.is_a?(Hash) &&
    signal[:segment].present? &&
    signal[:security_id].present? &&
    signal[:meta].is_a?(Hash) &&
    signal[:meta][:candidate_symbol].present?
end

def pick_valid?(pick)
  pick.is_a?(Hash) &&
    pick[:segment].present? &&
    pick[:security_id].present? &&
    pick[:symbol].present?
end
```

---

## Summary

### Current State
- ✅ **Working**: Basic signal generation, chain analysis, entry placement
- ❌ **Missing**: V3 module integration, signal deduplication, error retry logic
- ⚠️ **Risk**: Bypassing V3 modules means missing dynamic risk, premium filtering, ActiveCache

### Recommended Actions

1. **🔴 CRITICAL**: Integrate `Orders::EntryManager` to enable V3 architecture
2. **🟡 MEDIUM**: Add signal deduplication/cooldown logic
3. **🟡 MEDIUM**: Improve error handling with retry logic
4. **🟢 LOW**: Add performance monitoring/metrics
5. **🟢 LOW**: Add signal validation layer

### Expected Benefits After Integration

- ✅ **Better Risk Management**: Dynamic risk allocation based on trend score
- ✅ **Better Strike Selection**: Premium filtering and StrikeSelector integration
- ✅ **Better Position Tracking**: ActiveCache integration for PnL monitoring
- ✅ **Better Order Management**: Bracket order placement integration
- ✅ **Reduced Duplicates**: Cooldown logic prevents duplicate signals
- ✅ **Better Observability**: Performance metrics and error tracking

---

## Related Documentation

- [NEMESIS V3 Wiring Audit Report](./NEMESIS_V3_WIRING_AUDIT_REPORT.md)
- [Signal Generation Modularization](./SIGNAL_GENERATION_MODULARIZATION.md)
- [EntryManager Documentation](./orders_entry_manager.md)
- [TrendScorer Documentation](./signal_trend_scorer.md)
