# NEMESIS V3: StrikeSelector & IndexRules - Complete Implementation

## ✅ Implementation Complete

All files have been created, tested, and integrated. This is a **non-breaking enhancement** that uses existing infrastructure.

---

## 📁 Files Created

### Core Implementation
1. **`app/services/options/strike_selector.rb`**
   - Uses `DerivativeChainAnalyzer` (existing)
   - Applies index-specific rules
   - Returns normalized instrument hash
   - Integrates with `Live::TickCache`

2. **`app/services/options/index_rules/nifty.rb`**
   - NIFTY-specific validation rules
   - Lot size: 75, Min volume: 30K, Min premium: ₹25, Max spread: 0.3%

3. **`app/services/options/index_rules/banknifty.rb`**
   - BANKNIFTY-specific validation rules
   - Lot size: 15, Min volume: 50K, Min premium: ₹40, Max spread: 0.5%

4. **`app/services/options/index_rules/sensex.rb`**
   - SENSEX-specific validation rules
   - Lot size: 10, Min volume: 20K, Min premium: ₹30, Max spread: 0.3%

### Tests
5. **`spec/services/options/strike_selector_spec.rb`**
   - Unit tests for StrikeSelector
   - Tests candidate validation, LTP resolution, error handling

6. **`spec/services/options/index_rules/nifty_spec.rb`**
   - Unit tests for NIFTY rules
   - Tests liquidity, spread, premium validation

### Documentation
7. **`docs/strike_selector_integration_plan.md`**
   - Integration guide
   - Call site analysis
   - Migration recommendations

---

## 🔗 Integration Points

### Uses Existing Infrastructure
- ✅ **`Options::DerivativeChainAnalyzer`** - Gets candidates (no duplication)
- ✅ **`Live::TickCache`** - Resolves LTP (no duplication)
- ✅ **`Options::IndexRules`** - New, focused responsibility

### Compatible With
- ✅ **`Orders::EntryManager`** - Already handles normalized hashes
- ✅ **`Signal::Scheduler`** - Can use StrikeSelector optionally
- ✅ **`Entries::EntryGuard`** - Works with normalized pick format

---

## 📊 Call Site Analysis

### Current Usage of DerivativeChainAnalyzer

**Location:** `app/services/signal/scheduler.rb:103-111`

```ruby
analyzer = Options::DerivativeChainAnalyzer.new(
  index_key: index_cfg[:key],
  expiry: nil,
  config: chain_cfg
)
candidates = analyzer.select_candidates(limit: limit.to_i, direction: direction)
```

**Status:** ✅ **No changes required**
- DerivativeChainAnalyzer already does excellent scoring
- StrikeSelector is optional enhancement for index-rule validation
- Can be used in specific scenarios where strict validation is needed

### EntryManager Compatibility

**Location:** `app/services/orders/entry_manager.rb:93-104`

**Status:** ✅ **Already compatible**
- Updated to handle StrikeSelector output format
- Supports both DerivativeChainAnalyzer candidates and StrikeSelector hashes
- No breaking changes

---

## 🚀 Usage Examples

### Example 1: Direct Usage

```ruby
selector = Options::StrikeSelector.new

instrument = selector.select(
  index_key: 'NIFTY',
  direction: :bullish,
  expiry: nil, # Auto-select nearest
  config: { min_oi: 10_000, max_spread_pct: 0.03 }
)

if instrument
  # instrument is normalized hash ready for EntryManager
  entry_manager.process_entry(
    signal_result: instrument,
    index_cfg: index_cfg,
    direction: :bullish
  )
end
```

### Example 2: With EntryManager (Automatic)

```ruby
# EntryManager automatically handles StrikeSelector output
entry_manager = Orders::EntryManager.new

result = entry_manager.process_entry(
  signal_result: {
    index: 'NIFTY',
    exchange_segment: 'NSE_FNO',
    security_id: '49081',
    strike: 25_000,
    option_type: 'CE',
    ltp: 150.5,
    lot_size: 75,
    derivative_id: 123,
    symbol: 'NIFTY-25Jan2024-25000-CE'
  },
  index_cfg: index_cfg,
  direction: :bullish
)
```

### Example 3: Optional Integration in Scheduler

```ruby
# In Signal::Scheduler (optional enhancement)
def evaluate_strategies_priority(index_cfg, enabled_strategies)
  chain_cfg = AlgoConfig.fetch[:chain_analyzer] || {}

  # Option 1: Use DerivativeChainAnalyzer (existing, recommended)
  analyzer = Options::DerivativeChainAnalyzer.new(
    index_key: index_cfg[:key],
    expiry: nil,
    config: chain_cfg
  )
  candidates = analyzer.select_candidates(limit: 1, direction: direction)

  # Option 2: Use StrikeSelector for index-rule validation (optional)
  # selector = Options::StrikeSelector.new
  # instrument = selector.select(
  #   index_key: index_cfg[:key],
  #   direction: direction,
  #   config: chain_cfg
  # )
  # candidates = instrument ? [instrument] : []

  # ... rest of logic
end
```

---

## 📋 Normalized Instrument Hash Format

StrikeSelector returns a hash with this structure:

```ruby
{
  index: 'NIFTY',                    # Index key
  exchange_segment: 'NSE_FNO',       # Exchange segment
  security_id: '49081',              # Security ID (string)
  strike: 25_000,                    # Strike price (integer)
  option_type: 'CE',                 # Option type (CE/PE)
  ltp: 150.5,                        # Last traded price
  lot_size: 75,                      # Lot size
  spot: nil,                         # Spot price (optional)
  multiplier: 1,                     # Multiplier
  derivative: <Derivative>,           # Derivative record (optional)
  derivative_id: 123,                 # Derivative ID
  symbol: 'NIFTY-25Jan2024-25000-CE', # Option symbol
  iv: 20.5,                          # Implied volatility
  oi: 500_000,                       # Open interest
  score: 0.85,                       # Selection score
  reason: 'High score'                # Selection reason
}
```

This format is compatible with:
- `EntryManager.process_entry`
- `Entries::EntryGuard.try_enter`
- `Orders::Placer.buy_market!`

---

## 🧪 Testing

### Run Tests

```bash
# Run StrikeSelector tests
bundle exec rspec spec/services/options/strike_selector_spec.rb

# Run IndexRules tests
bundle exec rspec spec/services/options/index_rules/nifty_spec.rb
```

### Test Coverage

- ✅ StrikeSelector candidate validation
- ✅ LTP resolution from TickCache
- ✅ Index rule validation (liquidity, spread, premium)
- ✅ Error handling (unknown index, no candidates)
- ✅ NIFTY rules (lot size, ATM, validation)

---

## 🔄 Migration Recommendations

### Phase 1: Current State (✅ Complete)
- Files created and tested
- EntryManager compatible
- No breaking changes

### Phase 2: Optional Adoption (Recommended)
- Use StrikeSelector in specific scenarios:
  - When index-rule validation is critical
  - For new features requiring strict validation
  - In testing/validation workflows

### Phase 3: Full Integration (Optional, Not Recommended)
- Replace DerivativeChainAnalyzer calls with StrikeSelector
- Requires extensive testing
- Only if index-rule validation becomes mandatory

**Recommendation:** Keep existing DerivativeChainAnalyzer flow. Use StrikeSelector as an optional enhancement when needed.

---

## ⚠️ Important Notes

### No Duplication
- ✅ Uses existing `DerivativeChainAnalyzer` (no chain fetching duplication)
- ✅ Uses existing `Live::TickCache` (no tick storage duplication)
- ✅ Integrates with existing `EntryManager` (no order placement duplication)

### Backward Compatible
- ✅ Existing code continues to work
- ✅ DerivativeChainAnalyzer unchanged
- ✅ EntryManager handles both formats

### Performance
- ✅ Lightweight validation (O(1) checks)
- ✅ Reuses existing caches
- ✅ No additional API calls

---

## 📈 Next Steps

1. ✅ **Files created** - All implementation files ready
2. ✅ **Tests added** - RSpec tests in place
3. ✅ **Documentation** - Integration plan created
4. ⏳ **Optional adoption** - Use in specific scenarios as needed
5. ⏳ **Monitor usage** - Track performance and adoption

---

## 🎯 Summary

**StrikeSelector is a non-breaking enhancement that:**
- Uses existing DerivativeChainAnalyzer (no duplication)
- Applies index-specific validation rules
- Returns normalized instrument hashes
- Is fully compatible with EntryManager
- Can be adopted gradually or used in specific scenarios

**No immediate changes required** - StrikeSelector is ready for use when index-rule validation is needed.

---

## 📚 Related Documentation

- `docs/strike_selector_integration_plan.md` - Detailed integration guide
- `docs/nemesis_v3_event_bus_feed_listener.md` - EventBus & FeedListener docs
- `docs/options_buying_strategies.md` - Options buying strategies

