# Signal Entry Outcome Tracking

**Date:** 2026-03-25
**Branch:** feature/regime-aware-risk-engine
**Status:** Approved

## Problem

The Signals dashboard shows every generated signal but gives no indication of what happened after — whether the system attempted an entry, succeeded, or was blocked and why. Operators cannot distinguish a good signal that was blocked by a cooldown from one where no option strikes were available.

## Goal

For every signal row in the Signal Intelligence table, show a compact badge indicating entry outcome, and surface the exact reason when entry was not taken.

---

## Entry States

| State | Trigger |
|---|---|
| `entered` | Position successfully placed via `Orders::GatewayPaper` or `Orders::GatewayLive` |
| `blocked` | Entry attempted but rejected by the guard pipeline or `EntryPolicy` |
| `skipped` | Pre-conditions for entry not met; guard pipeline never reached |
| `pending` | Signal created; BOS state machine waiting for pullback, or outcome not yet recorded |

### `skipped` reasons (set in `Signal::Engine`)

| Condition | Reason string |
|---|---|
| `expiry_blocked` | `"expiry midday decay"` |
| ATR/expected move missing | `"missing ATR"` |
| No suitable option strikes | `"no suitable strikes"` |
| Market context gate failed | `"market context gate"` |
| `Portfolio::DrawdownGuard` active | `"drawdown guard active"` |

### `blocked` reasons (set in `EntryGuard`)

The raw `blocked:` string returned by the failing guard (e.g. `"cooldown active for index NIFTY"`, `"circuit breaker tripped: …"`). For `EntryPolicy` rejections the reasons array is joined with `"; "`.

---

## Data Storage

No DB migration. Two keys are written into the existing `metadata` jsonb column on `TradingSignal`:

```json
{
  "entry_outcome": "blocked",
  "entry_blocked_reason": "cooldown active for index NIFTY"
}
```

`metadata` is already included in the API JSON response via `as_json`, so no controller change is needed.

---

## Backend Changes

### 1. `Signal::Engine#run_for` (alpha layer)

- Capture the return value of `TradingSignal.create_from_analysis` into a local `signal` variable.
- At each early-return point after signal creation, call a small private helper `record_signal_skip(signal, reason)` that merges `entry_outcome: "skipped"` and `entry_blocked_reason: reason` into the signal's metadata and saves.
- Early-return points to instrument:
  - `expiry_blocked`
  - `expected_spot_move` nil/zero
  - `picks.blank?`
  - `mc_gate_blocked`
- Pass `signal:` into both `EntryGuard.try_enter` and `BosEntryEngine.run_for`.

### 2. `Entries::EntryGuard.try_enter` (alpha layer)

- Add optional keyword argument `signal: nil`.
- When `DrawdownGuard.triggered?` → call `signal&.record_entry_outcome("skipped", "drawdown guard active")`.
- When `entry_policy` not permitted → call `signal&.record_entry_outcome("blocked", policy.reasons.join("; "))`.
- When guard pipeline returns blocked → call `signal&.record_entry_outcome("blocked", reason)`.
- On successful order placement → call `signal&.record_entry_outcome("entered")`.

### 3. `TradingSignal` model (alpha layer)

Add a convenience instance method:

```ruby
def record_entry_outcome(outcome, reason = nil)
  update(metadata: (metadata || {}).merge(
    "entry_outcome" => outcome,
    "entry_blocked_reason" => reason
  ).compact)
end
```

### 4. `Entries::BosEntryEngine` (alpha layer)

- Accept and forward `signal:` kwarg to `EntryGuard.try_enter` calls.
- BOS signals that go into the state machine waiting for a pullback keep `pending` (no explicit write needed — default when key is absent).

---

## Frontend Changes

### `dashboard/src/views/Signals.vue`

**New computed field** on each signal in `processedSignals`:

```js
entryOutcome: sig.metadata?.entry_outcome || 'pending',
entryBlockedReason: sig.metadata?.entry_blocked_reason || null,
```

**New column** inserted between Strategy and Analysis:

- Header: `Entry`
- Cell: a badge `<span>` with a `title` attribute for the reason tooltip.

**Badge styles** (matching existing glass design system):

| State | Classes | Label |
|---|---|---|
| `entered` | `text-emerald-400 bg-emerald-500/10 border-emerald-500/20` | `● ENTERED` |
| `blocked` | `text-amber-400 bg-amber-500/10 border-amber-500/20` | `✗ BLOCKED` |
| `skipped` | `text-gray-500 bg-gray-500/10 border-gray-500/20` | `◌ SKIPPED` |
| `pending` | `text-gray-600` (no border/bg) | `— —` |

The `title` attribute carries `entryBlockedReason` for blocked/skipped states, providing the detail on hover without widening the table.

**Column count** changes from 6 → 7. The `colspan="6"` empty-state cell must be updated to `colspan="7"`.

---

## Out of Scope

- Filtering or sorting signals by entry outcome (future)
- Linking a signal row to the resulting `PositionTracker` record (future)
- Adding a DB index on `metadata->>'entry_outcome'` (not needed until filtering is required)
- Showing the entered option symbol in the table (covered by Positions tab)
