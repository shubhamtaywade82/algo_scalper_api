# Market Context (Regime Snapshot)

> **Note (2026-10-25):** This document was rewritten as part of audit S-001.
> The previous version described a `MarketPermissionGate` +
> `StrategyProfileSelector` + `ChainSignalExtractor` pipeline that has been
> removed as dead code. Only `MarketContext::RegimeComposer` remains, and
> it is consumed by AI/agent paths, not by `Signal::Engine` directly.

## What remains

`MarketContext::RegimeComposer` builds a `RegimeSnapshot` value object from
a candle series + index key. It is used by:

- `Ai::Agents::MarketAnalysisAgent` — advisory multi-agent pipeline
- `Ai::DynamicConfig::ContextBuilder` — LLM-driven config experiments
- `OptionsBuying::TradeScoringEngine` — live trade scoring

The composer delegates to three component analyzers:

| Component | File | Role |
|-----------|------|------|
| `MarketContext::RegimeComposer` | `app/services/market_context/regime_composer.rb` | Orchestrates analyzers, weights sub-scores into `conviction_score` |
| `MarketContext::StructureAnalyzer` | `app/services/market_context/structure_analyzer.rb` | Price structure (trending / ranging / choppy) |
| `MarketContext::VolatilityAnalyzer` | `app/services/market_context/volatility_analyzer.rb` | Volatility state (high / normal / low) |
| `MarketContext::ParticipationAnalyzer` | `app/services/market_context/participation_analyzer.rb` | Volume / participation assessment |

Output value object: `MarketContext::RegimeSnapshot`
(`app/services/market_context/regime_snapshot.rb`).

Fields include: `structure`, `strength`, `volatility_state`,
`participation`, `conviction_score`, `displacement`, legacy regime strings
from `MarketRegimeDetector`, and `raw` diagnostics.

## Configuration

```yaml
# config/algo.yml
market_context:
  enabled: false                    # Master switch
  regime_scoring:
    weights:
      trending_structure: 20
      displacement: 20
      vwap_not_chop: 15
      strong_strength: 15
      volatility_ok: 10
      participation_high: 10
      legacy_confidence: 10
```

The `regime_scoring.weights` block is read by `RegimeComposer` to compute
`conviction_score` as a weighted sum of sub-scores.

## What was removed (audit S-001, 2026-10-25)

The following components were deleted as dead code (zero live callers
outside their own specs):

- `Options::ChainSignalExtractor` — chain-side PCR / flow / premium analysis
- `Trading::MarketPermissionGate` — hard block gate on conviction / chain
- `Trading::StrategyProfileSelector` — maps `RegimeSnapshot` → profile symbol

Their config blocks (`market_context.gate`, `market_context.strategy_profiles`,
`market_context.chain_signal_extractor`) were also removed from
`config/algo.yml` as orphaned.

The `TrailingEngine#merge_strategy_profile_override!` method remains in
`app/services/trading/trailing_engine.rb` but is now a no-op: it reads
`@tracker.strategy_profile`, which was only ever set by the deleted
`StrategyProfileSelector`. Removing the no-op method is left as a
follow-up cleanup — it is harmless and the trailing-override mechanism
could be re-wired in the future without resurrecting the full selector.

## Related docs

- Signal pipeline overview: `docs/services/signal_services.md`
- AI subsystems analysis: `docs/architecture/ai_subsystems_analysis.md`
- Entry guard order: `docs/trading/entry_and_exit_rules.md`
