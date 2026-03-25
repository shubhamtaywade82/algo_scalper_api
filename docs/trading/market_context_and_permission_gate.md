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

## Regime snapshot

**Type:** `MarketContext::RegimeSnapshot` (`app/services/market_context/regime_snapshot.rb`).

Fields include: `structure`, `strength`, `volatility_state`, `participation`, `conviction_score`, `displacement`, legacy regime strings from `MarketRegimeDetector`, and `raw` diagnostics.

**Composer:** `app/services/market_context/regime_composer.rb`.

---

## Chain signals

**Class:** `Options::ChainSignalExtractor` — `app/services/options/chain_signal_extractor.rb`.

Uses `Options::FlowAnalyzer` for strike-level history; aggregates PCR from CE/PE OI in `chain_data[:oc]`. Near-expiry confidence penalty is configurable.

---

## Permission gate

**Class:** `Trading::MarketPermissionGate` — `app/services/trading/market_permission_gate.rb`.

Enforces thresholds from `market_context.gate` (conviction, chain confidence, participation, optional `require_premium_expansion`). Logs via `Observability::StructuredLog` with `event: 'entry_blocked'`, `stage: 'market_permission_gate'`.

---

## Position metadata and trailing

`strategy_profile` and market/chain keys are copied into `entry_metadata` and merged into `PositionTracker.meta` by `Entries::EntryGuard` (`merge_diagnostic_metadata!`).

`Trading::TrailingEngine` applies `risk.institutional_trailing.profiles.<profile>` overrides when meta contains `strategy_profile`. **Implementation:** `app/services/trading/trailing_engine.rb` (`merge_strategy_profile_override!`).

---

## Day-level profit protection

Do **not** duplicate a second profit floor: portfolio locking remains **`Portfolio::ProfitLockEngine`** + **`Portfolio::DrawdownGuard`** (`app/services/portfolio/`). Tune `profit_lock` in `config/algo.yml` instead of adding a parallel `Trade::ProfitProtector`.

---

## Related docs

- Signal pipeline overview: `docs/services/signal_services.md`
- Entry guard order: `docs/trading/entry_and_exit_rules.md`
- Institutional trailing defaults: `config/algo.yml` → `risk.institutional_trailing`
