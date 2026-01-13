# Trading Day Analysis: December 18, 2025 (Sensex Expiry Day)

## Executive Summary

**Date:** 2025-12-18
**Total Trades:** 163
**All Positions:** Exited
**Active Positions:** 0

## Overall Performance

### Final Statistics
- **Total Trades:** 163
- **Winners:** 81
- **Losers:** 82
- **Win Rate:** 49.69%
- **Realized PnL:** ₹18,451.50
- **Realized PnL %:** 18.45%

### Peak Performance Metrics
- **Max Profit Reached:** ₹19,400.76 (at 13:00-14:00 hour)
- **Max Loss Reached:** ₹-3,198.75 (at 15:00-16:00 hour)
- **Max Drawdown:** ₹3,198.75

## Time-Based Performance Analysis

### Performance by Hour (Exit Time)

| Hour            | Trades | PnL (₹)        | Win Rate   | Winners     | Losers                             |
| --------------- | ------ | -------------- | ---------- | ----------- | ---------------------------------- |
| 11:00-12:00     | 5      | -35.25         | 40.0%      | 2W/3L       | Early session, negative            |
| 12:00-13:00     | 39     | -1,072.75      | 53.85%     | 21W/18L     | Recovery phase                     |
| **13:00-14:00** | **57** | **+19,400.76** | **54.39%** | **31W/26L** | **BEST HOUR - Peak profitability** |
| 14:00-15:00     | 46     | +3,755.50      | 47.83%     | 22W/24L     | Continued profitability            |
| 15:00-16:00     | 16     | -3,198.75      | 31.25%     | 5W/11L      | Worst hour - late session losses   |

### Key Insights
- **Most Profitable Period:** 13:00-14:00 (₹19,400.76 profit)
- **Worst Period:** 15:00-16:00 (₹-3,198.75 loss)
- **Best Win Rate:** 12:00-13:00 and 13:00-14:00 (53.85% and 54.39%)
- **Worst Win Rate:** 15:00-16:00 (31.25%)

## Performance by Index

| Index      | Trades | PnL (₹)        | Win Rate   | Winners     | Losers                                               |
| ---------- | ------ | -------------- | ---------- | ----------- | ---------------------------------------------------- |
| **NIFTY**  | **87** | **+12,980.00** | **55.17%** | **48W/39L** | **Best performer**                                   |
| **SENSEX** | **62** | **+5,642.00**  | **41.94%** | **26W/36L** | Moderate performance                                 |
| BANKNIFTY  | 14     | +227.50        | 50.0%      | 7W/7L       | Limited trades - 7-day expiry filter applied mid-day |

**Note:** BankNIFTY had fewer trades because its expiry was farther than 7 days away. The 7-day expiry filter logic was added after the market opened, so some BankNIFTY trades occurred before the filter was activated, then trading stopped for this index.

**BankNIFTY Trade Timeline:**
- **First trade:** 11:42:16
- **Last trade:** 12:28:27
- **Duration:** ~46 minutes of trading before filter activation
- All 14 trades occurred between 11:42 AM and 12:28 PM, after which the 7-day expiry filter prevented further BankNIFTY trades

### Key Insights
- **NIFTY** was the most profitable index with 55.17% win rate
- **SENSEX** (expiry day) had lower win rate (41.94%) but still profitable
- **BANKNIFTY** had balanced performance with 50% win rate, but limited to 14 trades due to 7-day expiry filter being applied mid-day (BankNIFTY expiry was >7 days away)

## Entry Strategy Analysis

All trades used the same entry strategy:
- **Strategy:** `supertrend_adx`
- **Entry Path:** `supertrend_adx_1m_5m`
- **Timeframe:** 1m (primary)
- **Confirmation TF:** 5m
- **Validation Mode:** `balanced`
- **Strategy Mode:** `supertrend_adx`

## Exit Reason Analysis

### Top Exit Reasons by Frequency

| Exit Reason             | Trades   | PnL (₹)  | Win Rate | Notes                |
| ----------------------- | -------- | -------- | -------- | -------------------- |
| TP HIT (various %)      | Multiple | Positive | 100%     | Take profit exits    |
| SL HIT (various %)      | Multiple | Negative | 0%       | Stop loss exits      |
| time-based exit (15:20) | 6        | +965.00  | 33.33%   | End of session exits |

### Key Observations
- **TP HIT** exits were consistently profitable (100% win rate)
- **SL HIT** exits were consistently losses (0% win rate)
- **Time-based exits** at 15:20 had mixed results (33.33% win rate)

## Profitable Periods Timeline

The system was profitable after:
- **Trade #8** at 12:07:12 (₹226.75 cumulative)
- Continued profitability through most of the day
- Peak profitability reached during 13:00-14:00 hour

## Losing Periods Timeline

The system was in loss:
- **Trades #1-7:** Early session losses (₹-90.25 at trade #6)
- **15:00-16:00 hour:** Late session losses (₹-3,198.75)

## Entry/Exit Conditions

### Entry Conditions (All Trades)
- **Index:** BANKNIFTY, SENSEX, or NIFTY
- **Direction:** `long_pe` (Put options)
- **Strategy:** `supertrend_adx`
- **Entry Path:** `supertrend_adx_1m_5m`
- **Timeframe:** 1m primary, 5m confirmation
- **Validation Mode:** `balanced`

### Exit Conditions
- **Exit Paths:**
  - `take_profit` - TP HIT exits
  - `stop_loss_static_downward` - SL HIT exits
  - `time-based exit` - Session end exits
- **HWM PnL %:** Varied from 0% to 96% (high water mark reached before exit)

## Key Findings

### Strengths
1. **Strong Mid-Day Performance:** 13:00-14:00 hour generated ₹19,400.76 profit
2. **NIFTY Index Excellence:** 55.17% win rate with ₹12,980 profit
3. **Consistent Strategy:** All trades used same entry strategy (supertrend_adx)
4. **Overall Profitability:** Despite 49.69% win rate, system generated ₹18,451.50 profit

### Weaknesses
1. **Late Session Performance:** 15:00-16:00 hour had 31.25% win rate and ₹-3,198.75 loss
2. **Early Session Struggles:** 11:00-12:00 had negative PnL
3. **SENSEX Win Rate:** Lower win rate (41.94%) on expiry day
4. **Time-Based Exits:** Only 33.33% win rate for end-of-session exits

### Recommendations

1. **Consider Stopping Trading Earlier:** The 15:00-16:00 hour showed significant losses. Consider stopping trading at 15:00 or 15:15.

2. **Optimize Entry Timing:** Early session (11:00-12:00) showed negative performance. Consider delaying entries or adding additional filters.

3. **SENSEX Expiry Day Strategy:** On expiry days, consider:
   - Tighter stop losses
   - Earlier profit taking
   - Reduced position sizing

4. **Time-Based Exit Optimization:** The 33.33% win rate for time-based exits suggests these positions might benefit from earlier exits or different exit criteria.

5. **Capitalize on Best Hours:** The 13:00-14:00 hour was highly profitable. Consider:
   - Increasing position sizing during this period
   - Focusing on NIFTY during this time
   - Maintaining current strategy during this window

## Detailed Trade-by-Trade Analysis

For complete trade-by-trade analysis with cumulative stats after each exit, run:
```bash
bundle exec rake trading:analyze_day
```

This will show:
- Each trade's entry/exit times and prices
- Cumulative PnL after each trade
- Win rate progression
- Peak PnL and drawdown tracking
- Entry/exit conditions for each trade

## Metadata Analysis

All positions contain metadata with:
- Entry conditions (index, direction, strategy, timeframe, validation mode)
- Exit conditions (exit path, exit type, exit direction, HWM PnL %)
- Timing information (placed_at, exit_triggered_at)

**Note:** Indicator values (ADX, RSI, Supertrend) are not currently stored in PositionTracker metadata. These values are calculated dynamically during signal generation and stored in TradingSignal records, but not persisted with the position.

## Conclusion

Despite a win rate below 50% (49.69%), the system generated significant profit (₹18,451.50) due to:
1. **Asymmetric Risk/Reward:** Winners were larger than losers on average
2. **Strong Mid-Day Performance:** The 13:00-14:00 hour generated most of the day's profit
3. **NIFTY Excellence:** Strong performance on NIFTY index compensated for weaker SENSEX performance

The system demonstrated profitability on a Sensex expiry day, which is typically challenging due to increased volatility and theta decay.
