# Options System State

Last verified: 2026-04-07 12:38:24 IST
Last verified commit: `1045c5ab207055331c11520131c995a516c11ffc`

This file is a point-in-time snapshot. Re-read the referenced files before making behavior claims if the repo has moved.

## Critical Wiring

- `Signal::Engine` now calls the no-trade gate on the live path before execution gates and option picking.
  - Verified in `app/services/signal/engine.rb`
- The no-trade gate builds 1m/5m context, fetches nearest-expiry option-chain data, and blocks on insufficient context or failed validation.
  - Verified in `app/services/signal/engine.rb`
- `execute_supertrend_only_flow` still returns `effective_validation_mode: nil`.
  - Verified in `app/services/signal/engine.rb`

## Config State

- `signals.enable_no_trade_engine` is still `false`.
  - Verified in `config/algo.yml`
- No `validation_modes` block is present under `signals` as of last read.
  - Verified in `config/algo.yml`
- `enable_direction_gate` is `true`.
  - Verified in `config/algo.yml`
- `enable_smc_confluence_gating` is `false`.
  - Verified in `config/algo.yml`

## Expiry Logic

- `Strategies::ExpiryModel.trade_allowed?` blocks only the `:midday` session on expiry day.
  - Verified in `app/models/strategies/expiry_model.rb`
- Expiry sessions are currently:
  - `:morning` = 09:15-10:30
  - `:midday` = 10:30-13:00
  - `:afternoon` = 13:00-14:30
  - `:gamma_session` = 14:30-15:30
  - Verified in `app/models/strategies/expiry_model.rb`

## Option Selection State

- `Options::ChainAnalyzer.pick_strikes_with_qualification` does run:
  - `Options::FlowAnalyzer`
  - `Options::GammaRampDetector`
  - `Options::StrikeQualification::StrikeSelector`
  - `Options::StrikeQualification::ExpectedMoveValidator`
  - Verified in `app/services/options/chain_analyzer.rb`
- The selected leg is still rejected if `score < 140.0`.
  - Verified in `app/services/options/chain_analyzer.rb`

## Known Gaps

- No-trade protection is wired into the engine, but it is not active in production config until `enable_no_trade_engine` is turned on.
  - `config/algo.yml`
- `Entries::OptionChainWrapper` is still heuristic-grade:
  - improved from the earlier placeholder state, but still depends on single API snapshots rather than rolling strike history
  - now uses `previous_oi`, `previous_implied_volatility`, and nearest strike from spot/parity
  - Verified in `app/services/entries/option_chain_wrapper.rb`
- `Signal::Engine.execute_entry_gate` now applies a post-pick option premium gate using selected option `ltp` versus `prev_close`.
  - Verified in `app/services/signal/engine.rb`
- `Signal::MomentumValidator.check_premium_speed` still uses underlying/index candle closes from `series` in the pre-pick path.
  - The production-critical final gate is now contract-aware via `validate_option_pick`.
  - Verified in `app/services/signal/momentum_validator.rb`
- Supertrend-only flow still does not carry a concrete validation mode, which keeps validation behavior less explicit on that path.
  - Verified in `app/services/signal/engine.rb`

## Next Production Steps

1. Turn on `signals.enable_no_trade_engine` only after a controlled paper-mode smoke pass.
2. Replace `Entries::OptionChainWrapper` snapshot logic with strike-level rolling history for OI, IV, spread, and premium.
3. Replace the remaining pre-pick `check_premium_speed` index-based heuristic with actual option premium history.
4. Re-check expiry-day entry windows against NIFTY and SENSEX operating rules before enabling live order flow.
