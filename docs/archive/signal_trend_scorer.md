# Signal::TrendScorer

## Overview

`Signal::TrendScorer` computes a composite trend score (0-21) from multiple factors to assess the strength and direction of market trends. This score is used by `Signal::IndexSelector` to select the best index for trading.

**Note**: Volume scoring has been removed since volume is always 0 for indices/underlying spots.

## Usage

### Basic Usage

```ruby
instrument = IndexInstrumentCache.instance.get_or_fetch(index_key: :NIFTY)
scorer = Signal::TrendScorer.new(
  instrument: instrument,
  primary_tf: '1m',      # Primary timeframe (default: '1m')
  confirmation_tf: '5m'   # Confirmation timeframe (default: '5m')
)

result = scorer.compute_trend_score
# => {
#   trend_score: 15.5,
#   breakdown: {
#     pa: 4.0,   # Price action score (0-7)
#     ind: 5.5,  # Indicator score (0-7)
#     mtf: 6.0,  # Multi-timeframe score (0-7)
#     vol: 0.0   # Volume score (always 0 for indices)
#   }
# }
```

### Score Components

#### 1. PA Score (0-7): Price Action
- **Momentum (0-2 points)**: Recent price momentum (last 3 vs previous 3 candles)
- **Structure Breaks (0-2 points)**: Swing highs/lows indicating trend changes
- **Candle Patterns (0-2 points)**: Bullish candles, higher highs
- **Trend Consistency (0-1 point)**: Consistency of upward price movement

#### 2. IND Score (0-7): Technical Indicators
- **RSI (0-2 points)**: Relative Strength Index
  - RSI 50-70: Strong bullish (2 points)
  - RSI 40-80: Moderate bullish (1 point)
  - RSI > 30: Weak bullish (0.5 points)
- **MACD (0-2 points)**: Moving Average Convergence Divergence
  - MACD > Signal AND Histogram > 0: Strong bullish (2 points)
  - MACD > Signal: Bullish crossover (1 point)
  - Histogram > 0: Positive histogram (0.5 points)
- **ADX (0-2 points)**: Average Directional Index
  - ADX > 25: Very strong trend (2 points)
  - ADX > 20: Strong trend (1 point)
  - ADX > 15: Moderate trend (0.5 points)
- **Supertrend (0-1 point)**: Bullish Supertrend signal

#### 3. MTF Score (0-7): Multi-Timeframe Alignment
- **RSI Alignment (0-2 points)**: Both timeframes bullish
- **Trend Alignment (0-3 points)**: Both timeframes showing bullish Supertrend
- **Price Alignment (0-2 points)**: Both timeframes trending up

#### 4. VOL Score (removed)
- Volume scoring has been removed since volume is always 0 for indices/underlying spots
- The `vol` field in breakdown always returns `0.0`

## Integration

This service is used by:
- `Signal::IndexSelector` (Step 2) - To score each index and select the best one
- `Signal::Scheduler` (future) - For trend-based signal generation

## Timeframe Normalization

Timeframes are automatically normalized:
- `'1m'` → `'1'`
- `'5m'` → `'5'`
- `'15m'` → `'15'`
- `'60m'` → `'60'`

## Error Handling

The service handles errors gracefully:
- Missing candle data: Returns zero scores
- Calculation errors: Logs error and returns zero scores
- Insufficient data: Returns partial scores based on available data

## Testing

Run tests with:
```bash
bundle exec rspec spec/services/signal/trend_scorer_spec.rb
```

Test coverage includes:
- Initialization with various timeframes
- Score calculation with valid data
- Edge cases (no data, insufficient data, errors)
- Individual score component calculations
- Integration with real indicators

## Dependencies

- `CandleSeries` - For candle data and price action analysis
- `Indicators::Calculator` - For RSI, MACD, ADX calculations
- `Indicators::Supertrend` - For trend direction
- `Instrument` model - For accessing candle series via `candle_series(interval:)`

## Notes

- The composite score (0-21) is the sum of PA + IND + MTF scores (volume removed)
- Higher scores indicate stronger bullish trends
- Scores are rounded to 1 decimal place
- All scores are clamped to their valid ranges
- Volume is always 0 for indices, so VOL score is not calculated

