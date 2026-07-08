# Positions Page — Design

## Goal

A dedicated dashboard page listing all positions (open + closed) with filters, and a
detail drawer for inspecting one position's full trade lifecycle (entry context, PnL,
exit reason, and — when applicable — the strategy-platform guard trail that decided
whether it was entered).

## Scope

- New standalone route, does **not** touch the existing `OpenPositions` widget on
  `Dashboard.jsx` — that stays as-is.
- List + detail only. No editing, no closing positions from the detail drawer beyond
  the existing close action already on the list row.

## Backend

### `GET /api/positions/:id` (new)

`Api::PositionsController#show`, gated by `authenticate_dashboard_token!` (same as
`index`). 404 (`{ error: "not_found" }`) if no `PositionTracker` with that id.

Returns the same base fields as the list row (`Positions::Serializer.open`/`closed`)
plus:

- **Entry context**: `adx_at_entry` (parsed from `entry_context` jsonb if present),
  `iv_at_entry`, `vix_at_entry`, `dte_at_entry`, `atm_strike`, `expiry_date`,
  `entry_underlying_price`, `entry_tf`, `alpha_source`, `entry_path`.
- **Trailing/HWM state**: `high_water_mark_pnl`, `hwm_pnl_pct`, `secured_sl_price`,
  `breakeven_locked`, `profit_zone_state`.
- **Exit block** (closed positions only): `exit_reason`, `exit_path`,
  `exit_classification` (from `execution["classified_as"]`), `exited_at`.
- **Config snapshot**: `config_snapshot` and `config_version_hash` from the
  `PositionMetaSnapshot` association (`tracker.meta_snapshot`), nil if absent.
- **Strategy signal / guard trail**: if `Strategies::Signal.find_by(position_tracker_id:
  tracker.id)` returns a row, include `{ strategy_slug, action, confidence, outcome,
  reason, entry_result_reason: metadata["entry_result_reason"], guard_results:
  metadata["guard_results"] }`. `nil` if the position wasn't opened via the strategy
  platform (e.g. BOS engine / manual).
- **Raw meta**: `meta` jsonb as-is, for a collapsible "raw" section — this is a
  deliberate escape hatch for fields not worth individually mapping.

New `Positions::Serializer.detail(tracker)`: calls `open(tracker)` or `closed(tracker)`
depending on `tracker.exited_at.present?`, then merges the additional fields above.

### Routes

```ruby
get "positions/:id", to: "positions#show"
```
Added alongside the existing `positions`/`positions/:id/close` routes in
`config/routes.rb`.

## Frontend

### List page — `src/views/Positions.jsx`

- New route `/positions` registered in `App.jsx` (inside the protected `AppShell`
  group) and a new sidebar link in `Sidebar.jsx`.
- Open/Closed tab toggle. Closed tab reuses the filters the backend `index` action
  already supports: date picker (defaults today, populated from `available_dates`),
  index_key, option_type, outcome, side, sort column/direction — mirrors whatever
  control pattern `Reports.jsx` or `Ledger.jsx` already use for consistency (reuse,
  don't reinvent).
- Table built from the existing `Table`/`TableRow`/`TableCell` primitives and
  `PositionRow`-style formatting (`AnimatedNumber`, PnL coloring). Rows are clickable
  (whole row, not just a button) and open the detail drawer.
- Open-position rows subscribe to the same `usePositions` WS store already used by the
  Dashboard widget, so LTP/PnL update live without a separate polling loop. Closed rows
  are static, refetched only when filters change.

### Detail drawer — `src/components/positions/PositionDetailDrawer.jsx`

- Slide-over from the right, opened by clicking a row, closed via an X button, click
  outside the drawer, or Escape key.
- Fetches `GET /api/positions/:id` on open; for an already-open position in the list,
  merges live WS fields (ltp/pnl/pnl_pct/hwm_pnl) over the fetched snapshot the same
  way `usePositions.fetchPositions` already merges live fields over server data — no
  new merge logic, reuse `pickLiveFields`.
- Sections, top to bottom:
  1. Header: symbol, side badge, quantity, status (open/closed), paper/live badge.
  2. PnL block: entry price, current LTP (open) or exit price (closed), pnl, pnl_pct,
     hwm_pnl — same `AnimatedNumber` styling as the list row.
  3. Entry context: ADX/IV/VIX/DTE at entry, ATM strike, expiry date, entry timeframe,
     alpha source, entry path — plain label/value grid.
  4. Exit block (closed only): exit reason, exit path, classification, exited_at.
  5. Strategy & guards (only rendered if `strategy_signal` is non-null in the response):
     strategy slug, action, confidence, outcome, and the `guard_results` list rendered
     as an ordered list of `{guard name — pass/blocked}` badges, with the blocking
     guard's reason string shown inline on its row.
  6. Collapsible "Raw data" section at the bottom: `config_snapshot` and `meta` as
     pretty-printed JSON (`<details>`/accordion, collapsed by default).
- Loading state: skeleton/spinner while the detail fetch is in flight. Error state: a
  simple inline message if the fetch 404s or fails (position may have been closed and
  its trailing effects invalidated the id — treat as non-fatal).

## Error handling

- `show` action: 404 JSON on unknown id, consistent with other controllers' `not_found`
  pattern in this codebase.
- Detail drawer network failure: inline retry, doesn't crash the list page.

## Testing

- Request spec for `GET /api/positions/:id`: open position, closed position, position
  with a linked `Strategies::Signal` (asserts `guard_results` surfaces), position
  without one (asserts `strategy_signal: nil`), unknown id → 404.
- `Positions::Serializer.detail` unit spec covering the merge logic for both open and
  closed trackers.
- Frontend: no existing test harness convention found for Solid components in this
  repo beyond what's already there — match whatever (if anything) covers
  `OpenPositions.jsx`/`PositionRow.jsx` today; do not introduce a new test framework
  for this feature alone.

## Out of scope

- Editing SL/TP or closing a position from the drawer (the list's existing Close
  button remains the only close affordance).
- Charting/candle visualization inside the drawer.
- Changes to the Dashboard's existing `OpenPositions` widget.
