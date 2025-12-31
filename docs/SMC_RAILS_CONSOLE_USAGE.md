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

Uses the existing `Instrument#candles(interval:)`:

```ruby
series_5m  = instrument.candles(interval: "5")
series_15m = instrument.candles(interval: "15")
series_1h  = instrument.candles(interval: "60")
```

## (Optional) Trim Candle Windows

Recommended windows for intraday index options:

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
```

### Liquidity

```ruby
liquidity = Smc::Detectors::Liquidity.new(series_5m)
liquidity.buy_side_taken?
liquidity.sell_side_taken?
liquidity.sweep_direction
```

### Premium / Discount

```ruby
pd = Smc::Detectors::PremiumDiscount.new(series_15m)
pd.equilibrium
pd.premium?
pd.discount?
```

### Order Blocks

```ruby
obs = Smc::Detectors::OrderBlocks.new(series_5m)
obs.bullish
obs.bearish
```

### FVG

```ruby
fvg = Smc::Detectors::Fvg.new(series_5m)
fvg.gaps
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
```

## Run AVRZ (Timing Confirm Only)

AVRZ is designed to be used only as an LTF timing confirmation.

```ruby
Avrz::Detector.new(series_5m).rejection?
```

## Run Bias Engine (End-To-End Decision)

Returns `:call`, `:put`, or `:no_trade`.

```ruby
Smc::BiasEngine.new(instrument).decision
```

## (Optional) Call The Controller Endpoint

If you enabled the route, you can hit it from console:

```ruby
app.get(
  "/smc/decision",
  params: { security_id: "13", segment: "IDX_I", symbol_name: "NIFTY" }
)

app.response.status
app.response.parsed_body
```

