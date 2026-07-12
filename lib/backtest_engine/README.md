## Backtest Engine

Index‑driven options backtesting engine for NIFTY/SENSEX using DhanHQ v2 data.

### High‑level design

- **Index Engine**: Iterates index candles and derives structure/bias.
- **Option Mapper**: Maps index state + spot to strikes and option candles.
- **Strategy Engine**: Pluggable strategy objects that generate signals.
- **Execution Engine**: Simulates fills, slippage, theta, and PnL with lot sizes.
- **Runner**: Orchestrates the backtest over a date range.

The engine is intentionally framework‑free and can be mounted into
`algo_scalper_api` or any other app.

### Installation (local dev)

```bash
bundle install
rspec
```

### Installation (with DhanHQ)

In your main app (or IRB), add the `DhanHQ` gem and configure via ENV:

```ruby
gem "DhanHQ"
```

Required env vars (or token endpoint envs, see `dhanhq-client` docs):

- `DHAN_CLIENT_ID`
- `DHAN_ACCESS_TOKEN`

Then:

```bash
bundle install
cp .env.example .env  # fill credentials
bin/console           # starts IRB with BacktestEngine + DhanHQ configured
```

### Minimal Runner example (pre‑loaded data)

```ruby
require "backtest_engine"
require "backtest_engine"

index_candles = [...]  # array of BacktestEngine::Market::Candle
option_data   = {...}  # { call: { strike => [option_candles] }, put: { ... } }

runner = BacktestEngine::Runner.new(
  index_candles: index_candles,
  option_data: option_data,
  lot_size: 50
)

metrics = runner.run
puts metrics.total_pnl
```

### Supported indices

You can run a backtest for any of: **NIFTY**, **BANKNIFTY**, **SENSEX**. Pass `symbol:` to `DatasetBuilder`; it resolves DhanHQ security ID and you get the correct lot size from `InstrumentMetadata.lot_size(symbol)`.

### Runnable example – build dataset via DhanHQ (any index + period)

This example uses the **data layer** to fetch index + options for a given **symbol** and **date range**.

```ruby
require "backtest_engine"
require "dhan_hq"

BacktestEngine::DhanConfiguration.configure_with_env_or_token_endpoint

symbol = "NIFTY"   # or "BANKNIFTY", "SENSEX"
from  = "2025-01-01 09:15:00"
to    = "2025-01-01 15:30:00"

dataset = BacktestEngine::Data::DatasetBuilder.new(
  interval: 1,
  from: from,
  to: to,
  expiry_code: 0,    # 0 = current expiry, 1 = next, 2 = far
  symbol: symbol
).build

index_candles = dataset.map { |r| r[:index] }

option_data = {
  call: {},
  put:  {}
}

lot_size = BacktestEngine::Data::InstrumentMetadata.lot_size(symbol)

runner = BacktestEngine::Runner.new(
  index_candles: index_candles,
  option_data: option_data,
  lot_size: lot_size
)

metrics = runner.run
puts "#{symbol} total PnL: #{metrics.total_pnl.round(2)}"
```

To use a **raw DhanHQ security ID** instead of a symbol, pass `security_id:` and omit `symbol:`.

### Using the ExpiryTrendV1 strategy on a series

```ruby
series = BacktestEngine::Market::CandleSeries.new(index_candles)
i      = 50

indicators = {
  structure: series.structure[i - 2],
  pullback: series.pullback?(i),
  volume_spike: series.volume_spike?(i)
}

ltp = index_candles[i].close

result = BacktestEngine::Strategies::Runner.new(
  index_candle: index_candles[i],
  indicators: indicators,
  ltp: ltp
).call

signal  = result[:signal]   # {:action, :option_type, :strike, :sl_pct, :target_pct, ...}
context = result[:context]
```

