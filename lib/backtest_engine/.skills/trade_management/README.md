# Trade Management Skill

This skill functions as a specialized trade management controller. It manages open option contracts from entry confirmation until final execution exit.

## Trade Intelligence Layer

The Trade Management skill updates a stateful **Trade Intelligence** model under `data/knowledge_base/trade_management/`:

```text
data/knowledge_base/trade_management/
├── trade_timeline.json         # Log of price updates and actions taken
├── position_state_machine.json # Active tracking of the trade state
├── stop_loss_history.json       # Record of stop modifications
└── trade_journal/              # Individual trade performance folders
```

### Key Engines
* **Trend Capture Engine**: Computes how much of the underlying trend was captured.
* **Adaptive Trailing Engine**: Automatically shifts trailing algorithms (ATR, Swing-lows, Supertrend) based on current market regime.
* **Exit Intelligence Engine**: Compares multiple exit conditions (time, target, trailing, structure break) and chooses the exit option with the highest expectancy.
