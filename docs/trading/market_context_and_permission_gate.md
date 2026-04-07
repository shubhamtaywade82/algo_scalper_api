# Market Context and Permission Gate

Optional **alpha-layer** filters that run **after** strike qualification and **before** `EntryGuard.try_enter` / `BosEntryEngine`. They do not replace `MarketRegimeDetector` or `Options::ChainAnalyzer`; they compose and gate on top of them.

**Configuration:** `config/algo.yml` → `market_context:` (master `enabled`, `gate`, `regime_scoring`, `chain_signal_extractor`, `strategy_profiles`).

**Default:** `market_context.enabled: false` — no extra CPU or behavior until turned on.

---

## Flow

1. `Signal::Engine` already fetches `chain_data` via `instrument.fetch_option_chain(expiry_date)` (same object used for gamma analysis).
2. After `Options::ChainAnalyzer.pick_strikes_with_qualification` returns non-empty `picks`, if `market_context.enabled` is true:
   - `MarketContext::RegimeComposer` builds a `RegimeSnapshot` from `primary_series` + `MarketRegimeDetector`.
   - `Options::ChainSignalExtractor` reads chain flow/PCR/premium vs `FlowAnalyzer` cache.
   - `Trading::StrategyProfileSelector` sets `strategy_profile` for metadata.
3. If `market_context.gate.enabled` is true, `Trading::MarketPermissionGate` may block; on block, `Signal::Engine` logs and returns (no entry).

**Implementation:** `app/services/signal/engine.rb` (`evaluate_market_context_for_entry`).

---

## Regime Snapshot

**Type:** `MarketContext::RegimeSnapshot` (`app/services/market_context/regime_snapshot.rb`).

Fields include: `structure`, `strength`, `volatility_state`, `participation`, `conviction_score`, `displacement`, legacy regime strings from `MarketRegimeDetector`, and `raw` diagnostics.

**Composer:** `app/services/market_context/regime_composer.rb`

Component analyzers:
- `MarketContext::StructureAnalyzer` — price structure (trending/ranging/choppy)
- `MarketContext::VolatilityAnalyzer` — volatility state (high/normal/low)
- `MarketContext::ParticipationAnalyzer` — volume/participation assessment

Weights for `conviction_score` come from `config/algo.yml` → `market_context.regime_scoring`.

---

## Chain Signals

**Class:** `Options::ChainSignalExtractor` — `app/services/options/chain_signal_extractor.rb`.

Uses `Options::FlowAnalyzer` for strike-level history; aggregates PCR from CE/PE OI in `chain_data[:oc]`. Near-expiry confidence penalty is configurable (`chain_signal_extractor.near_expiry_penalty` in `market_context` config).

Output fields: `pcr`, `flow_score`, `premium_expansion`, `confidence`.

---

## Permission Gate

**Class:** `Trading::MarketPermissionGate` — `app/services/trading/market_permission_gate.rb`.

Enforces thresholds from `market_context.gate`:
- `min_conviction` — minimum conviction score from `RegimeSnapshot`
- `min_chain_confidence` — minimum chain signal confidence
- `min_participation` — minimum participation level
- `require_premium_expansion` (optional) — require bullish premium expansion

Logs via `Observability::StructuredLog` with `event: 'entry_blocked'`, `stage: 'market_permission_gate'` when blocking.

---

## Strategy Profiles

**Class:** `Trading::StrategyProfileSelector` — `app/services/trading/strategy_profile_selector.rb`.

Maps `RegimeSnapshot` → `strategy_profile` symbol (e.g., `:trending_expansion`, `:ranging_decay`). Profile is stored in:
- `entry_metadata[:strategy_profile]`
- `PositionTracker.meta['strategy_profile']`

**Trailing overrides:** `Trading::TrailingEngine#config_for_symbol` merges `risk.institutional_trailing.profiles.<strategy_profile>` overrides when `tracker.meta['strategy_profile']` is set.

**Implementation:** `app/services/trading/trailing_engine.rb` (`merge_strategy_profile_override!`).

---

## Position Metadata and Trailing

`strategy_profile` and market/chain keys are copied into `entry_metadata` and merged into `PositionTracker.meta` by `Entries::EntryGuard` (`merge_diagnostic_metadata!`).

This enables per-trade trailing behavior based on regime context at entry time.

---

## Day-Level Profit Protection

Do **not** duplicate a second profit floor at the market-context layer. Portfolio locking remains **`Portfolio::ProfitLockEngine`** + **`Portfolio::DrawdownGuard`** (`app/services/portfolio/`). Tune `profit_lock` in `config/algo.yml` instead of adding a parallel `Trade::ProfitProtector`.

---

## Configuration

```yaml
market_context:
  enabled: false                    # Master switch — no behavior when false
  regime_scoring:
    structure_weight: 0.4
    volatility_weight: 0.3
    participation_weight: 0.3
  chain_signal_extractor:
    near_expiry_penalty: 0.1
  gate:
    enabled: false                  # Hard block gate
    min_conviction: 0.6
    min_chain_confidence: 0.5
    min_participation: 0.4
    require_premium_expansion: false
  strategy_profiles:
    trending_expansion:
      # trailing overrides...
    ranging_decay:
      # trailing overrides...
```

---

## Related Docs

- Signal pipeline overview: `docs/services/signal_services.md`
- Entry guard order: `docs/trading/entry_and_exit_rules.md`
- Institutional trailing defaults: `config/algo.yml` → `risk.institutional_trailing`
