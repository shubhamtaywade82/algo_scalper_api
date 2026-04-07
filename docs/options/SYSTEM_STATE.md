# Options System State

Last verified: 2026-04-06 (docs sweep; align with `AlgoConfig` + `Signal::Engine`)

Last verified commit: `66b29751e784df95216b562ff9b48eb223656999`

This file is a point-in-time snapshot. Re-read the referenced files before making behavior claims if the repo has moved.

## Critical Wiring

- `Signal::Engine` applies **`halt_on_validation_failure`** immediately after the analysis branch when comprehensive validation fails (`config/algo.yml` → `signals.halt_on_validation_failure`).
- **Supertrend-only path** sets **`effective_validation_mode`** from regime: RANGING/CHOPPY → `conservative`, else `signals.validation_mode` (e.g. balanced). Options IV/theta checks use `signals.validation_modes` presets.
- **No-trade gate** runs after entry quality; **`entry_dte_guard`** runs after nearest expiry resolution. Both are in `app/services/signal/engine.rb`.
- `execute_options_analysis` can enforce **`options_analysis_gate`** when enabled (block on IV-rank / theta failure after pick path).

## Config State (representative — confirm in `config/algo.yml`)

- `signals.validation_modes` defines conservative / balanced / aggressive thresholds for comprehensive validation and options gates.
- `signals.enable_no_trade_engine` may be `false` for paper smoke (no-trade protection inactive until enabled).
- `signals.signal_tier` defaults to `standard`; `SIGNAL_TIER` env overrides. Presets live in `config/signal_tier_presets.yml`.
- `LIVE_TRADING` env forces effective `paper_trading.enabled` after YAML + DB + tier merge (`app/lib/algo_config.rb`).

## Expiry Logic

- `Strategies::ExpiryModel.trade_allowed?` blocks only the `:midday` session on expiry day (`app/models/strategies/expiry_model.rb`).
- Sessions: `:morning` 09:15-10:30, `:midday` 10:30-13:00, `:afternoon` 13:00-14:30, `:gamma_session` 14:30-15:30.

## Option Selection State

- `Options::ChainAnalyzer.pick_strikes_with_qualification` runs flow analysis, gamma ramp, strike qualification, expected-move validation (`app/services/options/chain_analyzer.rb`).
- Score reject threshold and chain scoring knobs remain in YAML / code — verify `chain_analyzer` and `ChainAnalyzer` when changing behaviour.

## Known Gaps

- No-trade protection is wired but may be off in YAML until a controlled paper pass (`enable_no_trade_engine`).
- `Entries::OptionChainWrapper` remains snapshot-oriented vs rolling strike history (`app/services/entries/option_chain_wrapper.rb`).
- IV rank on the signal path is still an **index volatility proxy**, not exchange IV percentile, unless you add that layer separately.

## Next Production Steps

1. Enable `signals.enable_no_trade_engine` only after a controlled paper-mode smoke pass.
2. Extend option-chain context with rolling OI/IV/spread history where research docs require it.
3. Re-check expiry-day windows against NSE/BSE rules before live order flow.
