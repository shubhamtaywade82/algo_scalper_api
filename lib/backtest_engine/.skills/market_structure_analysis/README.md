# Market Structure Analysis Skill

This skill functions as a specialized quantitative price action researcher. It maps the price action topology to detect breakouts, reversals, and liquidity sweeps.

## Structure Intelligence Database

The Market Structure Analysis skill updates a stateful **Structure Intelligence** database under `data/knowledge_base/structure/`:

```text
data/knowledge_base/structure/
├── swing_database.json        # Active swing highs, swing lows, and lookback sizes
├── bos_history.json           # Log of confirmed Break of Structure events
├── choch_history.json          # Log of trend reversal Character Changes
├── trend_history.json         # Macro and micro trend directions
├── liquidity_zones.json       # Unswept EQH/EQL pools and ranges
├── compression_zones.json     # Volatility squeeze metrics and durations
├── support_database.json      # Volume, OI, and price support boundaries
└── multi_tf_alignment.json    # Weekly/Daily/Hourly/Minute direction matrix
```

### Downstream Usage
* **Strategy Generator** queries `multi_tf_alignment.json` to verify if lower timeframe entries match the higher timeframe trend bias.
* **Trailing Stop Optimizer** queries `swing_database.json` to update trailing stops below the latest structural swing low.
* **Risk Manager** queries `compression_zones.json` to reduce sizing when market is in late distribution.
