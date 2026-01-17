# SMC Rails Console Usage

This shows how to run each SMC/AVRZ component from the Rails console.

## Start Console

From the project root:

```bash
bin/rails console
```

If you want to ensure classes are loaded (useful in some environments):

```ruby
Rails.application.eager_load!
```

## Load SMC Console Helpers (Recommended)

Load the helper functions for easier candle fetching:

```ruby
load 'lib/console/smc_helpers.rb'
```

This provides:
- `fetch_candles_with_history(instrument, interval:, target_candles:)` - Fetch candles with sufficient history
- `trading_days_for_candles(interval_minutes, target_candles)` - Calculate required trading days
- `trim_series(series, max_candles:)` - Trim series to last N candles

### Quick Example: Fetch NIFTY and SENSEX

For a quick start that fetches candles for both NIFTY and SENSEX:

```ruby
load 'lib/console/smc_example.rb'
fetch_nifty_and_sensex_candles
```

This will:
- Fetch 1H, 15m, and 5m candles for both NIFTY and SENSEX
- Store them in global variables: `$nifty_1h`, `$nifty_15m`, `$nifty_5m`, `$sensex_1h`, `$sensex_15m`, `$sensex_5m`
- Display the candle counts for each timeframe

## Get An Instrument

Use the existing lookup (no new fetchers):

```ruby
instrument = Instrument.find_by_sid_and_segment(
  security_id: "13",      # example
  segment_code: "IDX_I",
  symbol_name: "NIFTY"    # optional fallback
)
```

## Get CandleSeries Per Timeframe

**Important:** The default `candles(interval:)` method only fetches 2 trading days of data, which may not be enough for longer timeframes. Use the methods below to fetch sufficient data.

### Method 1: Default (Limited to 2 Trading Days)

```ruby
series_5m  = instrument.candles(interval: "5")
series_15m = instrument.candles(interval: "15")
series_1h  = instrument.candles(interval: "60")
# ⚠️ Warning: This may only return 15-20 candles for 1H interval
```

### Method 2: Fetch with Custom Date Range (Recommended)

For sufficient candles, calculate the required trading days:

```ruby
# Helper function to calculate trading days needed
def trading_days_for_candles(interval_minutes, target_candles)
  # Indian market hours: 9:15 AM to 3:30 PM = 6.25 hours per day
  hours_per_day = 6.25
  candles_per_day = (hours_per_day * 60) / interval_minutes.to_i
  trading_days = (target_candles.to_f / candles_per_day).ceil
  # Add 50% buffer for holidays, partial days, etc.
  (trading_days * 1.5).ceil
end

# Calculate required trading days
days_1h  = trading_days_for_candles(60, 60)   # => ~12 trading days
days_15m = trading_days_for_candles(15, 100)  # => ~8 trading days
days_5m  = trading_days_for_candles(5, 150)   # => ~6 trading days

# Fetch with custom date range
to_date = if defined?(Market::Calendar) && Market::Calendar.respond_to?(:today_or_last_trading_day)
            Market::Calendar.today_or_last_trading_day
          else
            Time.zone.today
          end

from_date_1h = if defined?(Market::Calendar) && Market::Calendar.respond_to?(:trading_days_ago)
                 Market::Calendar.trading_days_ago(days_1h)
               else
                 to_date - days_1h.days
               end

# Fetch 1H candles with sufficient history
raw_data_1h = instrument.intraday_ohlc(
  interval: "60",
  from_date: from_date_1h.to_s,
  to_date: to_date.to_s,
  days: days_1h
)

series_1h = CandleSeries.new(symbol: instrument.symbol_name, interval: "60")
series_1h.load_from_raw(raw_data_1h)
puts "Fetched #{series_1h.candles.count} candles for 1H interval"
```

### Method 3: Using Console Helpers (Recommended)

Load the helper file first:

```ruby
load 'lib/console/smc_helpers.rb'
```

Then use the helper function:

```ruby
# Fetch candles with sufficient history
series_1h  = fetch_candles_with_history(instrument, interval: "60", target_candles: 60)
series_15m = fetch_candles_with_history(instrument, interval: "15", target_candles: 100)
series_5m  = fetch_candles_with_history(instrument, interval: "5",  target_candles: 150)

# Check how many candles were fetched
puts "Fetched #{series_1h.candles.count} candles for 1H interval"
```

**Note:** If you prefer not to load the helper file, you can copy/paste the function definition from Method 2 above.

## (Optional) Trim Candle Windows

If you fetched more candles than needed, trim to the recommended windows:

- 1H: last 60 candles
- 15m: last 80–100 candles
- 5m: last 120–150 candles

Example (copy/paste):

```ruby
def trim_series(series, max_candles:)
  return series unless series&.respond_to?(:candles)

  trimmed = CandleSeries.new(symbol: series.symbol, interval: series.interval)
  series.candles.last(max_candles).each { |c| trimmed.add_candle(c) }
  trimmed
end

series_5m  = trim_series(series_5m,  max_candles: 150)
series_15m = trim_series(series_15m, max_candles: 100)
series_1h  = trim_series(series_1h,  max_candles: 60)
```

## Run Each SMC Detector

### Structure

```ruby
structure = Smc::Detectors::Structure.new(series_5m)
structure.trend
structure.bos?
structure.choch?

# Serialize to hash
structure.to_h
# => { trend: :bullish, bos: true, choch: false, swings: [...] }
```

### Liquidity

```ruby
liquidity = Smc::Detectors::Liquidity.new(series_5m)
liquidity.buy_side_taken?
liquidity.sell_side_taken?
liquidity.sweep_direction

# Serialize to hash
liquidity.to_h
# => { buy_side_taken: false, sell_side_taken: true, sweep_direction: :sell_side }
```

### Premium / Discount

```ruby
pd = Smc::Detectors::PremiumDiscount.new(series_15m)
pd.equilibrium
pd.premium?
pd.discount?

# Serialize to hash
pd.to_h
# => { high: 25000.0, low: 24800.0, equilibrium: 24900.0, price: 24950.0, premium: true, discount: false }
```

### Order Blocks

```ruby
obs = Smc::Detectors::OrderBlocks.new(series_5m)
obs.bullish
obs.bearish

# Serialize to hash
obs.to_h
# => { bullish: { open: 100.0, high: 105.0, low: 99.0, close: 104.0, timestamp: "2025-01-01T10:00:00Z" }, bearish: nil }
```

### FVG

```ruby
fvg = Smc::Detectors::Fvg.new(series_5m)
fvg.gaps

# Serialize to hash
fvg.to_h
# => { gaps: [{ type: :bullish, from: 100.0, to: 102.0 }, ...] }
```

## Run SMC Context (Composition)

`Smc::Context` bundles the detectors for a single timeframe.

```ruby
ctx = Smc::Context.new(series_15m)
ctx.structure.trend
ctx.liquidity.sweep_direction
ctx.pd.equilibrium
ctx.order_blocks.bullish
ctx.fvg.gaps

# Serialize entire context to hash
ctx.to_h
# => {
#   structure: { trend: :bullish, bos: true, choch: false, swings: [...] },
#   liquidity: { buy_side_taken: false, sell_side_taken: true, sweep_direction: :sell_side },
#   order_blocks: { bullish: {...}, bearish: nil },
#   fvg: { gaps: [...] },
#   premium_discount: { high: 25000.0, low: 24800.0, equilibrium: 24900.0, price: 24950.0, premium: true, discount: false }
# }
```

## Run AVRZ (Timing Confirm Only)

AVRZ is designed to be used only as an LTF timing confirmation.

```ruby
avrz = Avrz::Detector.new(series_5m)
avrz.rejection?

# Serialize to hash
avrz.to_h
# => { rejection: true, lookback: 20, min_wick_ratio: 1.8, min_vol_multiplier: 1.5 }
```

## Run Bias Engine (End-To-End Decision)

Returns `:call`, `:put`, or `:no_trade`.

```ruby
engine = Smc::BiasEngine.new(instrument)

# Get decision only
engine.decision
# => :call

# Get full details (decision + all timeframe contexts + AVRZ)
engine.details
# => {
#   decision: :call,
#   timeframes: {
#     htf: { interval: "60", context: { structure: {...}, liquidity: {...}, ... } },
#     mtf: { interval: "15", context: { structure: {...}, liquidity: {...}, ... } },
#     ltf: { interval: "5", context: { structure: {...}, liquidity: {...}, ... }, avrz: { rejection: true, ... } }
#   }
# }

# Analyze with AI bias validator (JSON output)
# Requires AI to be enabled in config/algo.yml (ai.enabled: true)
# and OLLAMA_BASE_URL or OPENAI_API_KEY to be set
engine.analyze_with_ai
# => "{\"market_bias\":\"bullish\",...}"
```

## (Optional) Call The Controller Endpoint

If you enabled the route, you can hit it from console:

```ruby
# Simple decision (default)
app.get(
  "/smc/decision",
  params: { security_id: "13", segment: "IDX_I", symbol_name: "NIFTY" },
  headers: { "Host" => "localhost" }
)
# Response: { "ok": true, "decision": "call" }

# Full details (add ?details=1 parameter)
app.get(
  "/smc/decision",
  params: { security_id: "13", segment: "IDX_I", symbol_name: "NIFTY", details: "1" },
  headers: { "Host" => "localhost" }
)
# Response: {
#   "ok": true,
#   "decision": "call",
#   "timeframes": {
#     "htf": { "interval": "60", "context": { "structure": {...}, "liquidity": {...}, ... } },
#     "mtf": { "interval": "15", "context": { "structure": {...}, ... } },
#     "ltf": { "interval": "5", "context": { "structure": {...}, ... }, "avrz": { "rejection": true, ... } }
#   }
# }

# With AI analysis (add ?ai=1 parameter, requires AI enabled)
app.get(
  "/smc/decision",
  params: { security_id: "13", segment: "IDX_I", symbol_name: "NIFTY", details: "1", ai: "1" },
  headers: { "Host" => "localhost" }
)
# Response: {
#   "ok": true,
#   "decision": "call",
#   "timeframes": {...},
#   "ai_analysis": "Market Structure Analysis:\n\n1. Market Structure Summary: ..."
# }

# Method 2: Direct service call (bypasses controller, recommended)
instrument = Instrument.find_by_sid_and_segment(
  security_id: "13",
  segment_code: "IDX_I",
  symbol_name: "NIFTY"
)
engine = Smc::BiasEngine.new(instrument)
engine.decision        # => :call
engine.details         # => { decision: :call, timeframes: {...} }
engine.analyze_with_ai # => AI analysis string (if AI enabled)

# Check response (safely - only after making a request)
# Make sure to call app.get() first, then check response
status_code = app.get(
  "/smc/decision",
  params: { security_id: "13", segment: "IDX_I", symbol_name: "NIFTY" },
  headers: { "Host" => "localhost" }
)

# Now safely check response
if app.response
  puts "Status: #{app.response.status}"
  puts "Body: #{JSON.pretty_generate(app.response.parsed_body)}"
else
  puts "No response available (request may have failed or not executed)"
end
```

**Note:** If you get a 403 "Blocked hosts" error, either:
- Use Method 2 (direct service call) - recommended
- Or ensure `config.hosts.clear` is set in `config/environments/development.rb`

**Note:** If `app.response` is `nil`, the request may have failed or not been executed. Always check `app.response` before accessing its properties.

