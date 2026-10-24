# Alpha Engine — Implementation Plan

This document outlines the end-to-end plan for integrating the **Options Buying Alpha Engine** into the `algo_scalper_api` Rails application. It builds upon the roadmap defined in `docs/ALPHA.md` and leverages existing production-ready components.

---

## 1. System Architecture

The Alpha Engine acts as an "Intelligence Layer" that feeds into the existing execution and risk management pipeline.

```text
Alpha Signal (Engine) → AlphaExecutionService → Derivative#buy_option! → Orders::Placer → DhanHQ API
                                ↓
                          Capital::Allocator (Sizing)
                                ↓
                          PositionTracker (State Management)
                                ↓
                          Existing Trailing/Breakeven/PNL Logic
```

### Key Integration Points
| Component | Integration Method |
| :--- | :--- |
| **Market Data** | Uses `Instrument#fetch_option_chain` and `HistoricalData` API. |
| **Sizing** | Routes through `Capital::Allocator` via existing `buy_option!` calls. |
| **Risk** | Validates against `CircuitBreaker` and `DrawdownGuard` before execution. |
| **Tracking** | Tags `PositionTracker` with `alpha_source` in the JSONB `meta` column. |
| **Audit** | Records all signals (executed or not) in a new `alpha_signals` table. |

---

## 2. Implementation Phases

### Phase 1: Foundation & Base Strategy (Infrastructure)
Establish core interfaces and data persistence.
- [ ] Create `Strategies::AlphaStrategy` base class.
- [ ] Add `alpha_strategies` section to `AlgoConfig`.
- [ ] Run Migration: Create `iv_snapshots` and `alpha_signals` tables.
- [ ] Implement `IvSnapshotJob` to pre-calculate daily ATM IV.

### Phase 2: Alpha Module Development
Implement the four core strategies as defined in the roadmap.
- [ ] **`MomentumAlpha`**: Breakout detection via ATR and Volume confirmation.
- [ ] **`VolExpansionAlpha`**: Mean-reversion targeting when IV percentile < 20%.
- [ ] **`EventAlpha`**: Directional positioning based on high-impact calendar events.
- [ ] **`ExpiryAlpha`**: Gamma-focused micro-breakout detection for 0DTE/1DTE.

### Phase 3: Orchestration & Jobs
Connect the strategies to the background worker system.
- [ ] **`SignalEngine`**: Orchestrator that runs strategies, deduplicates, and ranks by Expected Value (EV).
- [ ] **`AlphaScanJob`**: Recurring Solid Queue job (1-5 min) to trigger scans during market hours.
- [ ] **`AlphaExecutionJob`**: Specialized job for critical, high-confidence signal execution.

### Phase 4: Execution Bridge
Wire the signals into the existing order flow.
- [ ] **`AlphaExecutionService`**: The primary entry point for turning a signal into an order.
- [ ] **Modify `InstrumentHelpers#after_order_track!`**: Update to handle extended `meta` payload.
- [ ] **Modify `PositionTracker`**: Add `alpha_source`, `confidence`, and `ev` to `store_accessor :meta`.

### Phase 5: Validation & Deployment
Ensure safety and correctness.
- [ ] **RSpec Suite**: Add unit tests for each strategy using recorded market data.
- [ ] **Telegram Alerts**: Enable real-time notifications for all signals and fills.
- [ ] **Seed Config**: Update `AlgoConfig` via API to enable strategies in "Exploratory" mode.

---

## 3. Core Files to Add/Modify

### New Files
- `app/strategies/alpha_strategy.rb`
- `app/strategies/momentum_alpha.rb`
- `app/strategies/vol_expansion_alpha.rb`
- `app/strategies/event_alpha.rb`
- `app/strategies/expiry_alpha.rb`
- `app/services/signal_engine.rb`
- `app/services/alpha_execution_service.rb`
- `app/jobs/alpha_scan_job.rb`
- `app/jobs/alpha_execution_job.rb`
- `app/controllers/api/alpha_controller.rb`

### Modified Files
- `config/routes.rb`
- `app/models/concerns/instrument_helpers.rb`
- `app/models/position_tracker.rb`
- `app/models/derivative.rb`
- `app/models/instrument.rb`

---

## 4. Critical Safety Rules

1. **No-Averaging Rule**: If a `PositionTracker` is already active for a specific security, the alpha engine will block new entries for that security.
2. **Directional Locking**: The engine will not enter a `CE` position if an active `PE` position exists for the same index (and vice versa).
3. **25-Mod Limit Mitigation**: High-trailing signals will be routed via `SuperOrder` (Dhan server-side) to avoid burning the order modification limit.
4. **Kill Switch Integration**: All executions are gated by the global `CircuitBreaker`.

---

## 5. Success Metrics
- **Win Rate**: > 55% across all alpha sources.
- **Profit Factor**: > 1.5.
- **Execution Latency**: Signal-to-Order < 500ms.
- **Telemetry accuracy**: 100% of trades correctly tagged with their alpha source.
