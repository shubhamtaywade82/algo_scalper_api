/**
 * Takes profit out of the paper wallet for the last completed week or month. Needs DATABASE_URL and DHAN_CLIENT_ID.
 *
 *   npm run withdraw -- --period week|month [--pct 50]          shows what would be withdrawn
 *   npm run withdraw -- --period week|month [--pct 50] --confirm  withdraws it
 *   npm run withdraw -- --list                                   every withdrawal so far
 *
 * The amount is --pct of the period's net realised P&L; a flat or losing period withdraws nothing. Each period is
 * withdrawn once, and one cadence (weekly or monthly) is used throughout, so the same profit is never taken twice.
 * The agent must be stopped: it reads its capital once at start.
 */
import 'dotenv/config';
import type { Pool, PoolClient } from 'pg';
import { toPaise } from '../src/execution/paperStore.js';
import { createPostgresPool } from '../src/persistence/postgres.js';
import { validatePostgresUrl } from '../src/persistence/urls.js';

interface PeriodPnl {
  readonly period: string;
  readonly startDate: string;
  readonly endDate: string;
  readonly pnlInr: number;
}

const DEFAULT_WITHDRAW_PCT = 50;

function argument(name: string): string | undefined {
  const index = process.argv.indexOf(name);
  return index === -1 ? undefined : process.argv[index + 1];
}

/** Net realised P&L of the last completed IST week (Monday to Sunday) or calendar month. */
async function lastPeriodPnl(pool: Pool, clientId: string, cadence: 'week' | 'month'): Promise<PeriodPnl> {
  const label = cadence === 'week' ? `'W:' || to_char(s, 'IYYY-"W"IW')` : `'M:' || to_char(s, 'YYYY-MM')`;
  const { rows } = await pool.query<{ period: string; start_date: string; end_date: string; pnl: number }>(
    `WITH bounds AS (
       SELECT date_trunc($2, now() AT TIME ZONE 'Asia/Kolkata') - ('1 ' || $2)::interval AS s,
              date_trunc($2, now() AT TIME ZONE 'Asia/Kolkata') AS e
     )
     SELECT ${label} AS period, to_char(s, 'YYYY-MM-DD') AS start_date, to_char(e - interval '1 day', 'YYYY-MM-DD') AS end_date,
            COALESCE((SELECT SUM(realized_pnl_inr) FROM paper_positions
                      WHERE client_id = $1 AND status = 'CLOSED'
                        AND closed_at AT TIME ZONE 'Asia/Kolkata' >= s AND closed_at AT TIME ZONE 'Asia/Kolkata' < e), 0)::float8 AS pnl
     FROM bounds`,
    [clientId, cadence],
  );
  const row = rows[0];
  if (row === undefined) {
    throw new Error(`could not compute the last ${cadence} for client ${clientId}`);
  }
  return { period: row.period, startDate: row.start_date, endDate: row.end_date, pnlInr: row.pnl };
}

async function assertAgentStopped(pool: Pool, clientId: string): Promise<void> {
  const { rows } = await pool.query('SELECT 1 FROM leases WHERE client_id = $1 AND expires_at > now()', [`paper:${clientId}`]);
  if (rows.length > 0) {
    throw new Error('the paper agent holds its trading lease; stop it first, it reads its capital only at start');
  }
}

async function assertSameCadence(client: PoolClient, clientId: string, period: string): Promise<void> {
  const { rows } = await client.query<{ period: string }>(
    'SELECT period FROM paper_withdrawals WHERE client_id = $1 AND left(period, 2) <> left($2, 2) LIMIT 1',
    [clientId, period],
  );
  if (rows[0] !== undefined) {
    throw new Error(`withdrawal ${rows[0].period} used the other cadence; mixing weekly and monthly would take the same profit twice`);
  }
}

/** Debits the wallet and records the withdrawal and its cash entry in one transaction. */
async function recordWithdrawal(pool: Pool, clientId: string, pnl: PeriodPnl, amountInr: number): Promise<number> {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    await assertSameCadence(client, clientId, pnl.period);
    const inserted = await client.query(
      'INSERT INTO paper_withdrawals (client_id, period, period_pnl_inr, amount_inr) VALUES ($1, $2, $3, $4) ON CONFLICT DO NOTHING',
      [clientId, pnl.period, pnl.pnlInr, amountInr],
    );
    if ((inserted.rowCount ?? 0) === 0) {
      throw new Error(`${pnl.period} has already been withdrawn`);
    }
    // The wallet's CHECK refuses a withdrawal larger than the cash, and the whole transaction rolls back.
    const updated = await client.query<{ balance: number }>(
      'UPDATE paper_wallets SET balance_inr = balance_inr - $2, updated_at = now() WHERE client_id = $1 RETURNING balance_inr::float8 AS balance',
      [clientId, amountInr],
    );
    const balanceAfter = updated.rows[0]?.balance;
    if (balanceAfter === undefined) {
      throw new Error(`no paper wallet for client ${clientId}`);
    }
    await client.query(
      'INSERT INTO paper_wallet_entries (client_id, correlation_id, delta_inr, balance_after_inr, at) VALUES ($1, $2, $3, $4, now())',
      [clientId, `WITHDRAWAL:${pnl.period}`, -amountInr, balanceAfter],
    );
    await client.query('COMMIT');
    return balanceAfter;
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
}

async function listWithdrawals(pool: Pool, clientId: string): Promise<void> {
  const { rows } = await pool.query<{ period: string; pnl: number; amount: number; at: Date }>(
    'SELECT period, period_pnl_inr::float8 AS pnl, amount_inr::float8 AS amount, at FROM paper_withdrawals WHERE client_id = $1 ORDER BY at',
    [clientId],
  );
  let total = 0;
  for (const row of rows) {
    total += row.amount;
    console.log(`${row.period}  P&L ₹${row.pnl.toFixed(2)}  withdrawn ₹${row.amount.toFixed(2)}  at ${row.at.toISOString()}`);
  }
  console.log(`${rows.length} withdrawal(s), total ₹${toPaise(total).toFixed(2)}`);
}

async function withdraw(pool: Pool, clientId: string, cadence: 'week' | 'month'): Promise<void> {
  const pct = Number(argument('--pct') ?? DEFAULT_WITHDRAW_PCT);
  if (!(pct > 0 && pct <= 100)) {
    throw new Error(`--pct must be above 0 and at most 100, got ${argument('--pct')}`);
  }
  const pnl = await lastPeriodPnl(pool, clientId, cadence);
  const amountInr = pnl.pnlInr > 0 ? toPaise(Math.floor(pnl.pnlInr * pct) / 100) : 0;
  console.log(`${pnl.period} (${pnl.startDate} to ${pnl.endDate}): net P&L ₹${pnl.pnlInr.toFixed(2)}, ${pct}% = ₹${amountInr.toFixed(2)}`);
  if (amountInr <= 0) {
    console.log('nothing to withdraw');
    return;
  }
  if (!process.argv.includes('--confirm')) {
    console.log('dry run; add --confirm to withdraw');
    return;
  }
  await assertAgentStopped(pool, clientId);
  const balanceAfter = await recordWithdrawal(pool, clientId, pnl, amountInr);
  console.log(`withdrew ₹${amountInr.toFixed(2)}; wallet balance now ₹${balanceAfter.toFixed(2)}`);
}

async function main(): Promise<void> {
  const url = process.env['DATABASE_URL']?.trim();
  const clientId = process.env['DHAN_CLIENT_ID']?.trim();
  if (!url || !clientId) {
    throw new Error('DATABASE_URL and DHAN_CLIENT_ID are required');
  }
  validatePostgresUrl(url);
  const pool = createPostgresPool({ url, maxConnections: 2, connectTimeoutMs: 5_000, statementTimeoutMs: 15_000, onError: () => undefined });
  try {
    const cadence = argument('--period');
    if (process.argv.includes('--list')) {
      await listWithdrawals(pool, clientId);
    } else if (cadence === 'week' || cadence === 'month') {
      await withdraw(pool, clientId, cadence);
    } else {
      throw new Error('usage: withdraw.ts --period week|month [--pct <1-100>] [--confirm] | --list');
    }
  } finally {
    await pool.end();
  }
}

void main().catch((error: unknown) => {
  console.error(`withdraw: ${error instanceof Error ? error.message : String(error)}`);
  process.exitCode = 1;
});
