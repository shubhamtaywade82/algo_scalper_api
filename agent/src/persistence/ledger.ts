import type { TradingMode } from '../domain/mode.js';
import type { Pool, PoolClient } from 'pg';
import { LeaseLostError } from './lease.js';

export interface LedgerRecord {
  /** Unique across the table. 'runId:seq' for events from this build, 'legacy:day:line' for older lines. */
  readonly sourceKey: string;
  readonly runId: string | undefined;
  readonly seq: number | undefined;
  readonly tradingDay: string;
  /** ISO-8601 instant from the event itself. */
  readonly ts: string;
  readonly eventType: string;
  readonly underlying: string | undefined;
  readonly correlationId: string | undefined;
  /** The exact JSON object written to the journal file. */
  readonly record: Readonly<Record<string, unknown>>;
}

export interface RunRow {
  readonly runId: string;
  readonly instanceId: string;
  readonly mode: TradingMode;
  readonly clientId: string;
  readonly configFingerprint: string;
  readonly startedAt: string;
}

/**
 * Makes writes conditional on holding the lease. A live run passes its lease here, so a fenced-out process
 * cannot add trade events after another run has taken over. The check takes a shared lock on the lease row,
 * so a takeover cannot commit in the middle of a write.
 */
export interface LedgerFence {
  readonly clientId: string;
  readonly runId: string;
  readonly epoch: () => number | undefined;
}

const INSERT_CHUNK = 500;

/**
 * Runs `work` in one transaction, after proving this run still holds the lease at its epoch. The shared lock on
 * the lease row is held until commit, so a takeover cannot commit in the middle of the work. Any throw rolls the
 * transaction back. Every fenced write in the agent goes through here, so there is one definition of "held".
 */
export async function runFenced<T>(pool: Pool, fence: LedgerFence, work: (client: PoolClient) => Promise<T>): Promise<T> {
  const epoch = fence.epoch();
  if (epoch === undefined) {
    throw new LeaseLostError('this run does not hold the trading lease; the write is refused');
  }
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const held = await client.query(
      'SELECT 1 FROM leases WHERE client_id = $1 AND holder_run = $2 AND epoch = $3 AND expires_at > now() FOR SHARE',
      [fence.clientId, fence.runId, epoch],
    );
    if ((held.rowCount ?? 0) === 0) {
      throw new LeaseLostError('the trading lease moved to another run; the write is refused');
    }
    const result = await work(client);
    await client.query('COMMIT');
    return result;
  } catch (error) {
    await client.query('ROLLBACK').catch(() => undefined);
    throw error;
  } finally {
    client.release();
  }
}

/**
 * PostgreSQL text and jsonb reject the NUL character. One such string would fail its whole batch, and the
 * batch would retry forever. The NUL is dropped from the ledger copy only, so the journal keeps the original bytes.
 */
export function stripNul<T>(value: T): T {
  if (typeof value === 'string') {
    return value.replace(/\u0000/g, '') as T;
  }
  if (Array.isArray(value)) {
    return value.map((item: unknown) => stripNul(item)) as T;
  }
  if (value !== null && typeof value === 'object') {
    return Object.fromEntries(Object.entries(value).map(([k, v]) => [k, stripNul(v)])) as T;
  }
  return value;
}

/**
 * The ledger's read and write surface. Every write is idempotent on source_key, so a retried batch or a
 * backfill from the journal file cannot double-count an event.
 */
export class PostgresLedger {
  constructor(
    private readonly pool: Pool,
    private readonly fence?: LedgerFence,
  ) {}

  /** Inserts records that are not already present. Returns how many were new. */
  async insert(records: readonly LedgerRecord[]): Promise<number> {
    if (this.fence === undefined) {
      return this.insertRows(this.pool, records);
    }
    return runFenced(this.pool, this.fence, (client) => this.insertRows(client, records));
  }

  private async insertRows(queryable: Pool | PoolClient, records: readonly LedgerRecord[]): Promise<number> {
    let inserted = 0;
    for (let offset = 0; offset < records.length; offset += INSERT_CHUNK) {
      const chunk = records.slice(offset, offset + INSERT_CHUNK);
      const result = await queryable.query(
        `INSERT INTO trade_events (source_key, run_id, seq, trading_day, ts, event_type, underlying, correlation_id, record)
         SELECT * FROM unnest($1::text[], $2::uuid[], $3::integer[], $4::date[], $5::timestamptz[], $6::text[], $7::text[], $8::text[], $9::jsonb[])
         ON CONFLICT (source_key) DO NOTHING`,
        [
          chunk.map((r) => stripNul(r.sourceKey)),
          chunk.map((r) => r.runId ?? null),
          chunk.map((r) => r.seq ?? null),
          chunk.map((r) => r.tradingDay),
          chunk.map((r) => r.ts),
          chunk.map((r) => stripNul(r.eventType)),
          chunk.map((r) => (r.underlying === undefined ? null : stripNul(r.underlying))),
          chunk.map((r) => (r.correlationId === undefined ? null : stripNul(r.correlationId))),
          chunk.map((r) => JSON.stringify(stripNul(r.record))),
        ],
      );
      inserted += result.rowCount ?? 0;
    }
    return inserted;
  }

  /**
   * Every record for one IST trading day written by one mode and client, as the JSON lines the journal file held.
   * Order: runs by when they started, and events within a run by sequence. A clock step cannot reorder one run.
   * Paper and live never restore each other's events.
   */
  async dayLines(tradingDay: string, scope: { readonly mode: string; readonly clientId: string }): Promise<string[]> {
    const result = await this.pool.query<{ line: string }>(
      `SELECT t.record::text AS line FROM trade_events t
       LEFT JOIN runs r ON r.run_id = t.run_id
       WHERE t.trading_day = $1 AND t.record->>'mode' = $2 AND t.record->>'client' = $3
       ORDER BY COALESCE(r.started_at, t.ts), t.run_id NULLS FIRST, t.seq NULLS FIRST, t.id`,
      [tradingDay, scope.mode, scope.clientId],
    );
    return result.rows.map((row) => row.line);
  }

  /**
   * Rows for the day that carry no mode or client tag. They predate tagging, so they cannot be attributed to a
   * mode. Restore refuses to run while any exist, and the operator decides what to do with them.
   */
  async untaggedDayCount(tradingDay: string): Promise<number> {
    const result = await this.pool.query<{ count: string }>(
      `SELECT count(*)::text AS count FROM trade_events
       WHERE trading_day = $1 AND (record->>'mode' IS NULL OR record->>'client' IS NULL)`,
      [tradingDay],
    );
    return Number(result.rows[0]?.count ?? 0);
  }

  /** How many of these source keys are already in the ledger. Used to prove a backfill is complete. */
  async countSourceKeys(sourceKeys: readonly string[]): Promise<number> {
    if (sourceKeys.length === 0) {
      return 0;
    }
    const result = await this.pool.query<{ count: string }>(
      'SELECT count(*)::text AS count FROM trade_events WHERE source_key = ANY($1::text[])',
      [sourceKeys],
    );
    return Number(result.rows[0]?.count ?? 0);
  }

  /**
   * Runs for this client and mode that need an operator decision before a new run of that mode starts: runs that
   * never ended (a crash), and runs that ended with events still unconfirmed in the journal or ledger. Sandbox and
   * paper runs are reviewed separately from live runs, because they touch different accounts or none at all.
   */
  async runsNeedingReview(clientId: string, mode: TradingMode, exceptRunId: string): Promise<Array<{ runId: string; instanceId: string; startedAt: string; reason: string }>> {
    const result = await this.pool.query<{ run_id: string; instance_id: string; started_at: Date; unconfirmed_at_end: number; ended_at: Date | null }>(
      `SELECT run_id::text AS run_id, instance_id, started_at, unconfirmed_at_end, ended_at FROM runs
       WHERE client_id = $1 AND mode = $2 AND run_id <> $3 AND acknowledged = false
         AND (ended_at IS NULL OR unconfirmed_at_end > 0)
       ORDER BY started_at`,
      [clientId, mode, exceptRunId],
    );
    return result.rows.map((row) => ({
      runId: row.run_id,
      instanceId: row.instance_id,
      startedAt: row.started_at.toISOString(),
      reason:
        row.ended_at === null
          ? 'never ended'
          : `ended with ${row.unconfirmed_at_end} event(s) not confirmed in the journal and ledger`,
    }));
  }

  /**
   * The operator's record that a run has been reviewed. A run that never ended is closed by this call, and
   * the reason is kept on the row. Returns how many runs were acknowledged, which is 0 for a run already acknowledged.
   */
  async acknowledgeRun(runId: string, reason: string): Promise<number> {
    const result = await this.pool.query(
      `UPDATE runs SET acknowledged = true, ended_at = COALESCE(ended_at, now()), ended_reason = $2
       WHERE run_id = $1 AND acknowledged = false`,
      [runId, `acknowledged: ${reason}`],
    );
    return result.rowCount ?? 0;
  }

  async startRun(run: RunRow): Promise<void> {
    await this.pool.query(
      'INSERT INTO runs (run_id, instance_id, mode, client_id, config_fingerprint, started_at) VALUES ($1, $2, $3, $4, $5, $6)',
      [run.runId, run.instanceId, run.mode, run.clientId, run.configFingerprint, run.startedAt],
    );
  }

  /** Marks the run ended and records how many events were still unconfirmed at that moment. Only the first call counts. */
  async endRun(runId: string, reason: string, unconfirmed = 0): Promise<void> {
    await this.pool.query(
      'UPDATE runs SET ended_at = now(), ended_reason = $2, unconfirmed_at_end = $3 WHERE run_id = $1 AND ended_at IS NULL',
      [runId, reason, unconfirmed],
    );
  }

  async ping(): Promise<void> {
    await this.pool.query('SELECT 1');
  }
}
