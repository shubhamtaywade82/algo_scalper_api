# Market Research Analyst Skill

This skill functions as a specialized quantitative research agent responsible for analyzing the underlying index and options chain dynamics prior to strategy design or backtest runs.

## Stateful Market Knowledge Base (MKB)

Rather than performing redundant, computationally heavy indicators and calculations on every backtest run, the Market Research skill maintains a persistent **Market Knowledge Base** (MKB).

### Directory Layout

The MKB is cached in JSON format in the project's data store:
```text
data/knowledge_base/
├── instruments.json            # Resolved security IDs, lot sizes, and expirries
├── historical_statistics.json  # Interday and intraday statistics
├── session_statistics.json     # Period-specific ranges, volume, and volatility
├── regime_history.json         # Historical regime shifts and transition matrices
├── volatility_profiles.json    # IV rank, percentile, and realized vol bands
└── market_research_cache/      # Caching raw intermediate computation logs
```

### Knowledge Base Integration Flow

1. **Query Cache**: Downstream skills (e.g. `Strategy Generator`, `Backtest Validator`, `Risk Management`) check the MKB before triggering database or API loads.
2. **State Updates**: The Market Research analyst checks for missing timestamps or dates. If missing, it uses the DhanHQ API to update the corresponding profile and writes the updated state back to disk.

## How to Execute the Research Agent

To perform research on a target index:
```bash
# Run the market research command for a given period
bin/research --symbol NIFTY --from 2026-06-01 --to 2026-07-01
```
This script will load the market research skill workflow, validate data quality, compute profiles, and update `data/knowledge_base/`.
