#!/usr/bin/env node
import 'dotenv/config';
import type { Pool } from 'pg';
import { createPostgresPool } from '../src/persistence/postgres.js';
import { validatePostgresUrl } from '../src/persistence/urls.js';
import { toPaise } from '../src/execution/paperStore.js';
import { roundTripChargesInr } from '../src/options/pricing.js';

interface Issue {
  readonly severity: 'ERROR' | 'WARNING';
  readonly category: string;
  readonly entityId: string;
  readonly detail: string;
}

interface PositionRow {
  readonly position_id: string;
  readonly underlying: string;
  readonly exchange_segment: string;
  readonly quantity: number;
  readonly average_price: number;
  readonly stop_loss_price: number;
  readonly target_price: number;
  readonly status: 'OPEN' | 'CLOSED';
  readonly opened_at: Date;
  readonly closed_at: Date | null;
  readonly exit_price: number | null;
  readonly exit_reason: string | null;
  readonly realized_pnl: number | null;
}

interface OrderRow {
  readonly correlation_id: string;
  readonly position_id: string;
  readonly kind: string;
  readonly side: 'BUY' | 'SELL';
  readonly quantity: number;
  readonly price: number;
  readonly at: Date;
}

interface WalletEntryRow {
  readonly id: string;
  readonly correlation_id: string;
  readonly delta: number;
  readonly balance_after: number;
  readonly at: Date;
}

interface AuditSummary {
  readonly clientId: string;
  readonly initialInr: number;
  readonly currentBalanceInr: number;
  readonly ledgerBalanceInr: number;
  readonly openCount: number;
  readonly closedCount: number;
  readonly openCapitalInr: number;
  readonly realizedPnlInr: number;
  readonly withdrawnInr: number;
  readonly winCount: number;
  readonly lossCount: number;
  readonly issues: readonly Issue[];
}

function auditClosedPosition(pos: PositionRow, issues: Issue[]): { deltaCapital: number; deltaPnl: number; win: boolean; loss: boolean } {
  if (pos.exit_price === null || pos.exit_price < 0 || pos.closed_at === null || pos.realized_pnl === null) {
    issues.push({ severity: 'ERROR', category: 'POSITION_STATE', entityId: pos.position_id, detail: 'Closed position missing exit values' });
    return { deltaCapital: 0, deltaPnl: 0, win: false, loss: false };
  }
  const grossPnl = toPaise((pos.exit_price - pos.average_price) * pos.quantity);
  const charges = roundTripChargesInr({ quantity: pos.quantity, buyPrice: pos.average_price, sellPrice: pos.exit_price, exchangeSegment: pos.exchange_segment });
  const expectedPnl = toPaise(grossPnl - charges);
  // Closes recorded before the wallet deducted charges carry the gross figure: correct then, overstated now.
  if (Math.abs(grossPnl - pos.realized_pnl) <= 0.01 && charges > 0) {
    issues.push({ severity: 'WARNING', category: 'PNL_GROSS', entityId: pos.position_id, detail: `P&L ${pos.realized_pnl} booked before charges of ${charges}` });
  } else if (Math.abs(expectedPnl - pos.realized_pnl) > 0.01) {
    issues.push({ severity: 'ERROR', category: 'PNL_MATH', entityId: pos.position_id, detail: `P&L mismatch: expected ${expectedPnl} after charges, recorded ${pos.realized_pnl}` });
  }
  if (grossPnl < -toPaise(pos.average_price * pos.quantity)) {
    issues.push({ severity: 'ERROR', category: 'OPTIONS_RISK', entityId: pos.position_id, detail: 'Long option loss exceeds 100% of premium paid' });
  }
  return { deltaCapital: 0, deltaPnl: pos.realized_pnl, win: pos.realized_pnl >= 0, loss: pos.realized_pnl < 0 };
}

function auditSinglePosition(pos: PositionRow, issues: Issue[]): { deltaCapital: number; deltaPnl: number; win: boolean; loss: boolean } {
  if (pos.average_price <= 0 || pos.quantity <= 0) {
    issues.push({ severity: 'ERROR', category: 'OPTIONS_PRICING', entityId: pos.position_id, detail: `Invalid entry price (${pos.average_price}) or quantity (${pos.quantity})` });
  }
  if (!(pos.stop_loss_price < pos.average_price)) {
    issues.push({ severity: 'ERROR', category: 'OPTIONS_BRACKET', entityId: pos.position_id, detail: `Stop loss (${pos.stop_loss_price}) must be below entry (${pos.average_price})` });
  }
  if (pos.status === 'OPEN') {
    if (pos.closed_at !== null || pos.exit_price !== null || pos.realized_pnl !== null) {
      issues.push({ severity: 'ERROR', category: 'POSITION_STATE', entityId: pos.position_id, detail: 'Open position carries exit metadata' });
    }
    return { deltaCapital: pos.average_price * pos.quantity, deltaPnl: 0, win: false, loss: false };
  }
  return auditClosedPosition(pos, issues);
}

function auditPositions(positions: readonly PositionRow[], issues: Issue[]): { openCapital: number; realizedPnl: number; wins: number; losses: number } {
  let openCapital = 0;
  let realizedPnl = 0;
  let wins = 0;
  let losses = 0;
  for (const pos of positions) {
    const res = auditSinglePosition(pos, issues);
    openCapital = toPaise(openCapital + res.deltaCapital);
    realizedPnl = toPaise(realizedPnl + res.deltaPnl);
    if (res.win) wins += 1;
    if (res.loss) losses += 1;
  }
  return { openCapital, realizedPnl, wins, losses };
}

function auditOrders(orders: readonly OrderRow[], positions: readonly PositionRow[], issues: Issue[]): void {
  const posMap = new Map(positions.map((p) => [p.position_id, p]));
  const ordersByPos = new Map<string, OrderRow[]>();

  for (const o of orders) {
    if (!posMap.has(o.position_id)) {
      issues.push({ severity: 'ERROR', category: 'ORDER_INTEGRITY', entityId: o.correlation_id, detail: `Orphaned order points to missing position ${o.position_id}` });
    }
    const list = ordersByPos.get(o.position_id) ?? [];
    list.push(o);
    ordersByPos.set(o.position_id, list);
  }

  for (const pos of positions) {
    const posOrders = ordersByPos.get(pos.position_id) ?? [];
    const entries = posOrders.filter((o) => o.kind === 'ENTRY' && o.side === 'BUY');
    const exits = posOrders.filter((o) => o.kind !== 'ENTRY' && o.side === 'SELL');
    if (entries.length !== 1) {
      issues.push({ severity: 'ERROR', category: 'ORDER_MATCH', entityId: pos.position_id, detail: `Position has ${entries.length} buy entry orders (expected 1)` });
    } else if (entries[0] && (entries[0].quantity !== pos.quantity || Math.abs(entries[0].price - pos.average_price) > 0.01)) {
      issues.push({ severity: 'ERROR', category: 'ORDER_MATCH', entityId: pos.position_id, detail: 'Entry order price/quantity disagrees with position' });
    }
    const expectedExits = pos.status === 'CLOSED' ? 1 : 0;
    if (exits.length !== expectedExits) {
      issues.push({ severity: 'ERROR', category: 'ORDER_MATCH', entityId: pos.position_id, detail: `Position has ${exits.length} exit orders (expected ${expectedExits})` });
    }
  }
}

/** What a cash entry should move: an entry pays the premium, an exit returns cost plus the booked P&L, a withdrawal its amount. */
function expectedEntryDelta(entry: WalletEntryRow, records: LedgerRecords): number | undefined {
  const withdrawal = records.withdrawals.get(entry.correlation_id);
  if (withdrawal !== undefined) {
    return -withdrawal;
  }
  const order = records.orders.get(entry.correlation_id);
  if (order === undefined) {
    return undefined;
  }
  if (order.side === 'BUY') {
    return toPaise(-order.price * order.quantity);
  }
  const position = records.positions.get(order.position_id);
  return toPaise((position?.average_price ?? 0) * order.quantity + (position?.realized_pnl ?? 0));
}

interface LedgerRecords {
  readonly orders: ReadonlyMap<string, OrderRow>;
  readonly positions: ReadonlyMap<string, PositionRow>;
  readonly withdrawals: ReadonlyMap<string, number>;
}

function auditLedgerChain(entries: readonly WalletEntryRow[], records: LedgerRecords, initial: number, issues: Issue[]): number {
  let running = initial;

  for (const entry of entries) {
    const expectedDelta = expectedEntryDelta(entry, records);
    if (expectedDelta === undefined) {
      issues.push({ severity: 'ERROR', category: 'LEDGER_ORDER', entityId: entry.correlation_id, detail: 'Wallet entry has no matching order or withdrawal' });
      continue;
    }
    if (Math.abs(expectedDelta - entry.delta) > 0.01) {
      issues.push({ severity: 'ERROR', category: 'LEDGER_DELTA', entityId: entry.correlation_id, detail: `Delta mismatch: expected ${expectedDelta}, got ${entry.delta}` });
    }
    running = toPaise(running + entry.delta);
    if (Math.abs(running - entry.balance_after) > 0.01) {
      issues.push({ severity: 'ERROR', category: 'LEDGER_CHAIN', entityId: entry.correlation_id, detail: `Running balance mismatch: calculated ${running}, stored ${entry.balance_after}` });
    }
  }
  return running;
}

function printSummaryHeader(s: AuditSummary): void {
  const netEquity = toPaise(s.currentBalanceInr + s.openCapitalInr);
  const winRate = s.closedCount > 0 ? ((s.winCount / s.closedCount) * 100).toFixed(1) : '0.0';
  console.log('\n================== PAPER TRADING AUDIT & RECONCILIATION ==================');
  console.log(`Client ID:             ${s.clientId}`);
  console.log(`Starting Capital:      ₹${s.initialInr.toLocaleString('en-IN', { minimumFractionDigits: 2 })}`);
  console.log(`Current Cash Balance:  ₹${s.currentBalanceInr.toLocaleString('en-IN', { minimumFractionDigits: 2 })}`);
  console.log(`Committed in Open:     ₹${s.openCapitalInr.toLocaleString('en-IN', { minimumFractionDigits: 2 })} (${s.openCount} open)`);
  console.log(`Realized P&L:          ₹${s.realizedPnlInr >= 0 ? '+' : ''}${s.realizedPnlInr.toLocaleString('en-IN', { minimumFractionDigits: 2 })} (${s.closedCount} trades, ${winRate}% win rate)`);
  console.log(`Withdrawn:             ₹${s.withdrawnInr.toLocaleString('en-IN', { minimumFractionDigits: 2 })}`);
  console.log(`Total Account Equity:  ₹${netEquity.toLocaleString('en-IN', { minimumFractionDigits: 2 })}`);
  console.log('--------------------------------------------------------------------------');
  console.log('MATHEMATICAL & OPTIONS INVARIANTS:');
}

function printReport(s: AuditSummary): void {
  printSummaryHeader(s);
  const errors = s.issues.filter((i) => i.severity === 'ERROR');
  const warnings = s.issues.filter((i) => i.severity === 'WARNING');
  if (errors.length === 0 && warnings.length === 0) {
    console.log('✔ All orders, positions, wallet entries, and P&L calculations reconcile perfectly.');
    console.log('✔ Options constraints verified: positive premiums, loss capped at 100%, and valid brackets.');
    console.log('==========================================================================\n');
    return;
  }
  for (const issue of s.issues) {
    const symbol = issue.severity === 'ERROR' ? '✖' : '⚠';
    console.log(`${symbol} [${issue.category}] (${issue.entityId}): ${issue.detail}`);
  }
  console.log(`\nReconciliation completed with ${errors.length} error(s) and ${warnings.length} warning(s).`);
  console.log('==========================================================================\n');
}

async function loadAuditRecords(pool: Pool, clientId: string): Promise<{
  wallet: { initial: number; balance: number };
  positions: PositionRow[];
  orders: OrderRow[];
  entries: WalletEntryRow[];
  withdrawals: Map<string, number>;
}> {
  const walletRes = await pool.query<{ initial: number; balance: number }>(
    'SELECT initial_inr::float8 AS initial, balance_inr::float8 AS balance FROM paper_wallets WHERE client_id = $1',
    [clientId],
  );
  const wallet = walletRes.rows[0];
  if (!wallet) throw new Error(`No paper wallet found for client ${clientId}`);

  const [posRes, orderRes, entryRes, withdrawalRes] = await Promise.all([
    pool.query<PositionRow>('SELECT position_id, underlying, exchange_segment, quantity, average_price::float8 AS average_price, stop_loss_price::float8 AS stop_loss_price, target_price::float8 AS target_price, status, opened_at, closed_at, exit_price::float8 AS exit_price, exit_reason, realized_pnl_inr::float8 AS realized_pnl FROM paper_positions WHERE client_id = $1 ORDER BY opened_at', [clientId]),
    pool.query<OrderRow>('SELECT correlation_id, position_id, kind, side, quantity, price::float8 AS price, at FROM paper_orders WHERE client_id = $1 ORDER BY at', [clientId]),
    pool.query<WalletEntryRow>('SELECT id::text AS id, correlation_id, delta_inr::float8 AS delta, balance_after_inr::float8 AS balance_after, at FROM paper_wallet_entries WHERE client_id = $1 ORDER BY paper_wallet_entries.id', [clientId]),
    pool.query<{ period: string; amount: number }>('SELECT period, amount_inr::float8 AS amount FROM paper_withdrawals WHERE client_id = $1', [clientId]),
  ]);
  const withdrawals = new Map(withdrawalRes.rows.map((row) => [`WITHDRAWAL:${row.period}`, row.amount]));
  return { wallet, positions: posRes.rows, orders: orderRes.rows, entries: entryRes.rows, withdrawals };
}

function verifyGlobalParity(wallet: { initial: number; balance: number }, posAudit: { openCapital: number; realizedPnl: number }, withdrawn: number, issues: Issue[]): void {
  const expectedBalance = toPaise(wallet.initial + posAudit.realizedPnl - posAudit.openCapital - withdrawn);
  if (Math.abs(expectedBalance - wallet.balance) > 0.01) {
    issues.push({ severity: 'ERROR', category: 'GLOBAL_BALANCE', entityId: 'wallet', detail: `Balance parity failed: Initial (${wallet.initial}) + PnL (${posAudit.realizedPnl}) - OpenCapital (${posAudit.openCapital}) - Withdrawn (${withdrawn}) = ${expectedBalance}, but wallet balance is ${wallet.balance}` });
  }
}

function buildSummary(clientId: string, wallet: { initial: number; balance: number }, posAudit: { openCapital: number; realizedPnl: number; wins: number; losses: number }, withdrawn: number, ledgerBalance: number, positions: readonly PositionRow[], issues: readonly Issue[]): AuditSummary {
  return {
    clientId,
    initialInr: wallet.initial,
    currentBalanceInr: wallet.balance,
    ledgerBalanceInr: ledgerBalance,
    openCount: positions.filter((p) => p.status === 'OPEN').length,
    closedCount: positions.filter((p) => p.status === 'CLOSED').length,
    openCapitalInr: posAudit.openCapital,
    realizedPnlInr: posAudit.realizedPnl,
    withdrawnInr: withdrawn,
    winCount: posAudit.wins,
    lossCount: posAudit.losses,
    issues,
  };
}

async function main(): Promise<void> {
  const url = process.env['DATABASE_URL']?.trim();
  if (!url) throw new Error('DATABASE_URL is required');
  validatePostgresUrl(url);

  const clientId = process.env['DHAN_CLIENT_ID']?.trim() ?? '1104216308';
  const pool = createPostgresPool({ url, maxConnections: 2, connectTimeoutMs: 5_000, statementTimeoutMs: 15_000, onError: () => undefined });
  const issues: Issue[] = [];

  try {
    const { wallet, positions, orders, entries, withdrawals } = await loadAuditRecords(pool, clientId);
    const posAudit = auditPositions(positions, issues);
    auditOrders(orders, positions, issues);
    const records = {
      orders: new Map(orders.map((o) => [o.correlation_id, o])),
      positions: new Map(positions.map((p) => [p.position_id, p])),
      withdrawals,
    };
    const ledgerBalance = auditLedgerChain(entries, records, wallet.initial, issues);
    const withdrawn = toPaise([...withdrawals.values()].reduce((sum, amount) => sum + amount, 0));
    verifyGlobalParity(wallet, posAudit, withdrawn, issues);

    printReport(buildSummary(clientId, wallet, posAudit, withdrawn, ledgerBalance, positions, issues));
    if (issues.some((i) => i.severity === 'ERROR')) process.exitCode = 1;
  } finally {
    await pool.end();
  }
}

void main().catch((error: unknown) => {
  console.error('reconcile failed:', error instanceof Error ? error.message : error);
  process.exitCode = 1;
});
