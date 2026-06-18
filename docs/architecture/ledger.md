# Double-Entry Paper Ledger

Financial source of truth for paper mode. `position_trackers` remains authoritative
for open risk, exits, and PnL display; the ledger books cash, deployed premium,
fees, and realized PnL.

## Chart Of Accounts

| Code | Type | Normal balance |
|------|------|----------------|
| `cash` | asset | debit |
| `premium_deployed` | asset | debit |
| `brokerage_expense` | expense | debit |
| `realized_pnl` | income | credit |
| `opening_equity` | equity | credit |

## Posting Rules

### Opening balance (seed)

- DR `cash` — `paper_trading.balance` from config
- CR `opening_equity` — same amount

Idempotency: `opening_balance:paper`

### Entry BUY (paper fill)

- DR `premium_deployed` — qty × fill_price
- CR `cash` — gross premium
- DR `brokerage_expense` — entry fee
- CR `cash` — entry fee

Idempotency: `entry:{position_tracker_id}`

### Exit SELL (paper fill)

- DR `cash` — gross exit proceeds (qty × exit_price)
- CR `premium_deployed` — entry cost basis (qty × entry_price)
- CR `realized_pnl` — profit, or DR `realized_pnl` — loss
- DR `brokerage_expense` — exit fee
- CR `cash` — exit fee

Idempotency: `exit:{position_tracker_id}`

## Invariants

1. Every journal entry: sum(debits) = sum(credits)
2. `idempotency_key` is unique per journal entry
3. Paper mode may block entries that would make `cash` negative when
   `ledger.block_negative_cash` is true (default)

## Wallet Snapshot

`Ledger::WalletReader.snapshot(mode: :paper)` returns:

- `cash` — ledger `cash` account balance
- `utilized` / `exposure` — `premium_deployed` balance
- `mtm` — sum of unrealized PnL from active `position_trackers.paper`
- `equity` — cash + utilized + mtm

When `ledger.paper_enabled` is true, `GatewayPaper#wallet_snapshot` uses the reader.

## Reconciliation

`Ledger::ReconciliationJob` compares ledger cash to the legacy wallet calculation
and logs drift when `ledger.shadow_mode` is true.

## Live Mode (Phase 2 — Deferred)

Live broker ledger is out of scope for v1. Future work:

1. Add `orders` and `fills` tables keyed to DhanHQ order IDs
2. Post journals from `Live::OrderUpdateHandler` on confirmed fills (not gateway ack)
3. Align `pending` → `active` tracker transitions with broker truth
4. Reconcile `GatewayLive#wallet_snapshot` to ledger + DhanHQ funds API

See `lib/tasks/ledger.rake` for paper backfill; live fill-driven posting remains unimplemented.
