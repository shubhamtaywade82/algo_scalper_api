# Backtesting System - Usage Guide

## 📁 Files Created

```
app/
├── services/
│   └── backtest_service.rb         # Main backtesting engine
├── strategies/
│   ├── simple_momentum_strategy.rb # 3-bar momentum strategy
│   └── inside_bar_strategy.rb      # Inside bar breakout strategy
lib/tasks/
└── backtest.rake                    # Rake tasks for easy execution
```

---

## 🚀 How to Run Backtests

### 1. Test NIFTY with default settings (5min, 90 days)

```bash
rake "backtest:run[NIFTY]"
```

### 2. Test BANKNIFTY with custom settings

```bash
rake "backtest:run[BANKNIFTY,5,60]"
# Format: rake "backtest:run[SYMBOL,INTERVAL,DAYS]"
```

### 3. Test all indices at once

```bash
rake "backtest:indices"
# Tests NIFTY, BANKNIFTY, FINNIFTY with same settings
```

### 4. Export results to CSV

```bash
rake "backtest:export[NIFTY,5,90,nifty_results.csv]"
```

---

## 📊 Example Output

```
============================================================
BACKTEST RESULTS: NIFTY
============================================================
Period: Last 90 days | Interval: 5 min
------------------------------------------------------------
Total Trades:      42
Winning Trades:    19 (45.24%)
Losing Trades:     23
------------------------------------------------------------
Avg Win:           +52.3%
Avg Loss:          -28.7%
Max Win:           +78.5%
Max Loss:          -30.0%
------------------------------------------------------------
Total P&L:         +127.4%
Expectancy:        +3.03% per trade
============================================================
```

---

## 🎯 What You're Testing

### Strategy 1: SimpleMomentumStrategy (Default)

**Entry Rules:**
- 3 consecutive green candles (for CE) OR 3 consecutive red candles (for PE)
- Current candle body > 70% of its range
- Closes in top/bottom 30% of range
- Only trades 10:00 AM - 2:30 PM

**Exit Rules:**
- Stop Loss: -30%
- Target: +50%
- Trailing Stop: Activates at +40%, trails by 10%
- Time Exit: 3:20 PM

### Strategy 2: InsideBarStrategy

**Entry Rules:**
- Previous candle forms inside bar (high < parent high, low > parent low)
- Current candle breaks above (CE) or below (PE) inside bar
- Close confirms breakout

**Exit Rules:** Same as above

---

## 🔧 How to Use Different Strategies

In your rake "task or console:"

```ruby
# Test with Inside Bar Strategy
result = BacktestService.run(
  symbol: 'NIFTY',
  interval: '5',
  days_back: 90,
  strategy: InsideBarStrategy  # Change this
)

result.print_summary
```

---

## 💻 Using in Rails Console

```ruby
# Start console
rails c

# Run backtest
result = BacktestService.run(
  symbol: 'NIFTY',
  interval: '5',
  days_back: 90,
  strategy: SimpleMomentumStrategy
)

# Print summary
result.print_summary

# Access raw data
summary = result.summary

# Get all trades
summary[:trades].each do |trade|
  puts "#{trade[:signal_type]} | Entry: ₹#{trade[:entry_price]} | P&L: #{trade[:pnl_percent]}% | Reason: #{trade[:exit_reason]}"
end

# Filter only winning trades
winners = summary[:trades].select { |t| t[:pnl_percent] > 0 }
puts "#{winners.size} winning trades"

# Analyze by exit reason
by_reason = summary[:trades].group_by { |t| t[:exit_reason] }
by_reason.each do |reason, trades|
  avg_pnl = trades.sum { |t| t[:pnl_percent] } / trades.size
  puts "#{reason}: #{trades.size} trades, avg P&L: #{avg_pnl.round(2)}%"
end
```

---

## 📈 What to Look For

### ✅ Good Strategy Indicators

- **Win rate: 45-60%** (with your 30%/50% exits)
- **Expectancy: +2% or higher** per trade
- **Max loss never exceeds -30%** (stop loss working)
- **Avg win > Avg loss** (positive risk/reward)

### ❌ Poor Strategy Indicators

- **Win rate < 40%** (too many losers)
- **Expectancy negative** (losing money overall)
- **Many trades hit stop loss** (entries are wrong)
- **Few trades total** (strategy too restrictive)

---

## 🎓 Next Steps After Backtesting

### If Results Are Good (Expectancy > +2%):

1. **Run on all 3 indices** to confirm consistency
2. **Test different intervals** (1min, 15min) to find sweet spot
3. **Paper trade** the strategy for 2 weeks manually
4. **Then automate** with confidence

### If Results Are Poor:

1. **Analyze exit reasons**: Are most losses hitting stop loss? (entry timing wrong)
2. **Check time of day**: Do most losses happen at certain hours?
3. **Adjust parameters**: Try 35%/-45% instead of 30%/-50%
4. **Test other strategy** (switch from Momentum to InsideBar or vice versa)

---

## 🛠️ Creating Your Own Strategy

Create `app/strategies/your_strategy.rb`:

```ruby
class YourStrategy
  attr_reader :series

  def initialize(series:)
    @series = series
  end

  def generate_signal(index)
    return nil if index < 5 # Need lookback

    candle = series.candles[index]

    # Your logic here
    # Return { type: :ce/:pe, confidence: 0-100 } or nil

    if your_bullish_condition?
      return { type: :ce, confidence: 70 }
    end

    if your_bearish_condition?
      return { type: :pe, confidence: 70 }
    end

    nil
  end
end
```

Then test it:

```bash
# In console
result = BacktestService.run(
  symbol: 'NIFTY',
  strategy: YourStrategy
)
```

---

## 🔍 Troubleshooting

### "No OHLC data available"
- Check if instrument exists: `Instrument.find_by(symbol_name: 'NIFTY')`
- Verify DhanHQ API is working: `instrument.intraday_ohlc(interval: '5', days: 2)`

### "No trades executed"
- Strategy might be too restrictive
- Check if trading hours are correct (10 AM - 2:30 PM)
- Lower confidence threshold or relax entry conditions

### API Rate Limits
- Add `sleep 2` between multiple backtests
- Use cached data when possible
- Run backtests during off-market hours

---

## 📝 Important Notes

1. **Backtest ≠ Future Results**: Past performance doesn't guarantee future success
2. **Slippage not included**: Real trades will have 2-5 point slippage
3. **Options decay not modeled**: This backtests INDEX movements, not actual option premiums
4. **Start small**: Even if backtest looks great, start with 1 lot in live trading

---

## ✨ Summary

You now have a **fully functional backtesting system** that:

✅ Fetches 90 days of historical OHLC data from DhanHQ
✅ Simulates bar-by-bar trading with realistic exits
✅ Calculates win rates, expectancy, and detailed statistics
✅ Supports multiple strategies (easily add your own)
✅ Exports results to CSV for analysis
✅ Integrates seamlessly with your existing Rails setup

**Next action:** Run your first backtest and see if SimpleMomentumStrategy has an edge!

```bash
rake "backtest:run[NIFTY]"
```