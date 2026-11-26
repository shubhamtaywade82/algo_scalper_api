import { strict as assert } from 'node:assert';
import { randomUUID } from 'node:crypto';
import { mkdir, mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { after, before, describe, it } from 'node:test';
import { Client, Pool } from 'pg';
import { loadConfig, LIVE_ACK_PHRASE } from '../src/config.js';
import { restoreDayBook } from '../src/ops/dayState.js';
import { EventLog, journalFileName } from '../src/ops/eventLog.js';
import { DayBook } from '../src/risk/dayBook.js';
import { backfillDay } from '../src/persistence/backfill.js';
import { RedisCacheStore } from '../src/persistence/cache.js';
import { Lease, LeaseLostError, PostgresLeaseStore } from '../src/persistence/lease.js';
import { PostgresLedger, type LedgerRecord } from '../src/persistence/ledger.js';
import { MIGRATIONS } from '../src/persistence/migrations.js';
import { createPostgresPool, migrate } from '../src/persistence/postgres.js';
import { connectRedis, type RedisOptions } from '../src/persistence/redis.js';
import { RedisRateGate } from '../src/persistence/rateGate.js';
import { secretsOf } from '../src/persistence/redact.js';
import { openSession } from '../src/persistence/session.js';
import { istEpoch } from './support/fixtures.js';

/**
 * Integration tests against real PostgreSQL and Redis. They run when TEST_DATABASE_URL and TEST_REDIS_URL
 * are set; CI provides both as service containers. Without them the suite is skipped, and the unit tests
 * still cover the logic through in-memory stores.
 *
 * Each group uses its own trading day and client id, so no group can see another group's rows.
 *
 * In CI (CI=true) a missing URL fails the module instead of skipping, so a misconfigured service cannot
 * turn the integration gate into a silent pass.
 */
const PG_URL = process.env['TEST_DATABASE_URL'];
const REDIS_URL = process.env['TEST_REDIS_URL'];
if (process.env['CI'] === 'true' && (PG_URL === undefined || REDIS_URL === undefined)) {
  throw new Error('CI is set but TEST_DATABASE_URL and TEST_REDIS_URL are not; the persistence integration suite must not be skipped in CI');
}
const suffix = randomUUID().replace(/-/g, '').slice(0, 12);
const DB_NAME = `agent_test_${suffix}`;
const SCOPE = { mode: 'paper' as const, clientId: 'TEST' };

let pool: Pool | undefined;
let ledger: PostgresLedger | undefined;
let journalDir = '';

before(async () => {
  if (PG_URL === undefined) {
    return;
  }
  // A fresh database per run, so a failed run cannot leave state behind for the next one.
  const admin = new Client({ connectionString: PG_URL });
  await admin.connect();
  await admin.query(`CREATE DATABASE "${DB_NAME}"`);
  await admin.end();
  const url = new URL(PG_URL);
  url.pathname = `/${DB_NAME}`;
  pool = createPostgresPool({
    url: url.toString(),
    maxConnections: 6,
    connectTimeoutMs: 5_000,
    statementTimeoutMs: 10_000,
    onError: () => undefined,
  });
  ledger = new PostgresLedger(pool);
  journalDir = await mkdtemp(join(tmpdir(), 'ledger-it-'));
});

after(async () => {
  if (pool !== undefined) {
    await pool.end();
    const admin = new Client({ connectionString: PG_URL });
    await admin.connect();
    await admin.query(`DROP DATABASE IF EXISTS "${DB_NAME}" WITH (FORCE)`);
    await admin.end();
  }
  if (journalDir !== '') {
    await rm(journalDir, { recursive: true, force: true });
  }
});

async function freshRun(mode: 'paper' | 'live' = 'paper', clientId = SCOPE.clientId): Promise<string> {
  const runId = randomUUID();
  await ledger!.startRun({
    runId,
    instanceId: 'test-host',
    mode,
    clientId,
    configFingerprint: 'a'.repeat(64),
    startedAt: new Date().toISOString(),
  });
  return runId;
}

describe('PostgreSQL migrations', { skip: PG_URL === undefined }, () => {
  it('applies every migration once, then nothing on a second run', async () => {
    const first = await migrate(pool!, MIGRATIONS);
    assert.deepEqual(first.applied, MIGRATIONS.map((m) => m.version));
    const second = await migrate(pool!, MIGRATIONS);
    assert.deepEqual(second.applied, []);
    assert.equal(second.alreadyApplied, MIGRATIONS.length);
  });

  it('lets two processes run the migrations at once without a conflict', async () => {
    const results = await Promise.all([migrate(pool!, MIGRATIONS), migrate(pool!, MIGRATIONS)]);
    assert.deepEqual(results.map((r) => r.applied), [[], []]);
  });

  it('refuses to start when an applied migration has been edited, and leaves the record unchanged', async () => {
    const version = MIGRATIONS[0]!.version;
    const { rows } = await pool!.query<{ checksum: string }>('SELECT checksum FROM schema_migrations WHERE version = $1', [version]);
    const original = rows[0]!.checksum;
    await pool!.query("UPDATE schema_migrations SET checksum = 'tampered' WHERE version = $1", [version]);
    await assert.rejects(migrate(pool!, MIGRATIONS), /changed after it was applied/);
    const after = await pool!.query<{ checksum: string }>('SELECT checksum FROM schema_migrations WHERE version = $1', [version]);
    assert.equal(after.rows[0]?.checksum, 'tampered', 'a refused start does not rewrite the record');
    await pool!.query('UPDATE schema_migrations SET checksum = $2 WHERE version = $1', [version, original]);
  });

  it('refuses to start when the database holds a migration this build does not know', async () => {
    await pool!.query("INSERT INTO schema_migrations (version, checksum) VALUES ('999_future', 'x')");
    try {
      await assert.rejects(migrate(pool!, MIGRATIONS), /does not know/);
    } finally {
      await pool!.query("DELETE FROM schema_migrations WHERE version = '999_future'");
    }
  });
});

describe('PostgreSQL ledger', { skip: PG_URL === undefined }, () => {
  const DAY = '2026-10-12';

  it('is idempotent on source key, so a retried batch cannot double-count', async () => {
    const runId = await freshRun();
    const row: LedgerRecord = {
      sourceKey: `${runId}:1`,
      runId,
      seq: 1,
      tradingDay: DAY,
      ts: '2026-10-12T09:45:00.000Z',
      eventType: 'entry_submitted',
      underlying: 'NIFTY',
      correlationId: 'ENT-1',
      record: { type: 'entry_submitted', run: runId, seq: 1, underlying: 'NIFTY', mode: 'paper', client: 'TEST' },
    };
    assert.equal(await ledger!.insert([row]), 1);
    assert.equal(await ledger!.insert([row]), 0);
    assert.equal(await ledger!.countSourceKeys([row.sourceKey, 'missing:1']), 1);
  });

  it('returns a day in replay order for one mode and client only, with a legacy line first at the same instant', async () => {
    const day = '2026-10-14';
    const runId = await freshRun();
    const ts = '2026-10-14T10:00:00.000Z';
    const tagged = { mode: 'paper', client: 'TEST' };
    await ledger!.insert([
      { sourceKey: `legacy:${day}:1`, runId: undefined, seq: undefined, tradingDay: day, ts, eventType: 'legacy', underlying: undefined, correlationId: undefined, record: { type: 'legacy' } },
      { sourceKey: `${runId}:1`, runId, seq: 1, tradingDay: day, ts, eventType: 'later', underlying: undefined, correlationId: undefined, record: { type: 'later', run: runId, seq: 1, ...tagged } },
      { sourceKey: `${runId}:2`, runId, seq: 2, tradingDay: day, ts: '2026-10-14T10:01:00.000Z', eventType: 'other', underlying: undefined, correlationId: undefined, record: { type: 'other', run: runId, seq: 2, mode: 'live', client: 'TEST' } },
    ]);
    assert.equal(await ledger!.untaggedDayCount(day), 1, 'the legacy row is counted as untagged');
    const types = (await ledger!.dayLines(day, SCOPE)).map((line) => JSON.parse(line).type);
    assert.deepEqual(types, ['later'], 'the untagged row and the live row are not restored into a paper scope');
  });

  it('exposes closed trades through the v_closed_trades view', async () => {
    const day = '2026-10-15';
    const runId = await freshRun();
    await ledger!.insert([
      {
        sourceKey: `${runId}:9`,
        runId,
        seq: 9,
        tradingDay: day,
        ts: '2026-10-15T10:20:00.000Z',
        eventType: 'trade_closed',
        underlying: 'NIFTY',
        correlationId: undefined,
        record: {
          type: 'trade_closed',
          positionId: 'ENT-9',
          contract: 'NIFTY 24000 CE',
          quantity: 75,
          entryPrice: 100,
          exitPrice: 120,
          pnlInr: 1500,
          reason: 'TARGET',
          mode: 'paper',
          client: 'TEST',
        },
      },
    ]);
    const { rows } = await pool!.query<{ position_id: string; pnl_inr: string; exit_reason: string }>(
      "SELECT position_id, pnl_inr::text, exit_reason FROM v_closed_trades WHERE position_id = 'ENT-9'",
    );
    assert.deepEqual(rows, [{ position_id: 'ENT-9', pnl_inr: '1500', exit_reason: 'TARGET' }]);
  });

  it('marks a run ended once, keeping the first reason', async () => {
    const runId = await freshRun();
    await ledger!.endRun(runId, 'SHUTDOWN');
    await ledger!.endRun(runId, 'LATER');
    const { rows } = await pool!.query<{ ended_reason: string }>('SELECT ended_reason FROM runs WHERE run_id = $1', [runId]);
    assert.equal(rows[0]?.ended_reason, 'SHUTDOWN');
  });

  it("lists unended live runs for a client, and an acknowledgement closes one with the reviewer's reason", async () => {
    const client = `ACK${suffix}`;
    const crashed = await freshRun('live', client);
    const current = await freshRun('live', client);
    const listed = await ledger!.runsNeedingReview(client, 'live', current);
    assert.deepEqual(listed.map((r) => r.runId), [crashed]);
    assert.equal(await ledger!.acknowledgeRun(crashed, 'checked the broker book'), 1);
    assert.equal(await ledger!.acknowledgeRun(crashed, 'again'), 0, 'an acknowledged run is not acknowledged twice');
    assert.deepEqual(await ledger!.runsNeedingReview(client, 'live', current), []);
    const { rows } = await pool!.query<{ ended_reason: string }>('SELECT ended_reason FROM runs WHERE run_id = $1', [crashed]);
    assert.equal(rows[0]?.ended_reason, 'acknowledged: checked the broker book');
  });
});

describe('journal to ledger, end to end', { skip: PG_URL === undefined }, () => {
  const DAY = '2026-10-20';
  const EVENTS_PER_DAY = 7;

  /** The events one trading day produces: two entries and closes, an operator block and clear, and a breach. */
  function writeDay(log: EventLog, clock: { now: number }, day: string = DAY): void {
    const at = (hhmm: string) => {
      clock.now = istEpoch(day, hhmm);
    };
    at('09:45');
    log.record('entry_submitted', { underlying: 'NIFTY', correlationId: 'ENT-1' });
    at('10:20');
    log.record('trade_closed', { underlying: 'NIFTY', positionId: 'ENT-1', pnlInr: -1200, reason: 'STOP_LOSS' });
    at('10:30');
    log.record('operator_entry_block', { reason: 'operator entry block (10:30)' });
    at('10:45');
    log.record('operator_entry_clear', {});
    at('11:00');
    log.record('entry_submitted', { underlying: 'NIFTY', correlationId: 'ENT-2' });
    at('11:10');
    log.record('trade_closed', { underlying: 'NIFTY', positionId: 'ENT-2', pnlInr: -2600, reason: 'DAILY_LOSS' });
    at('11:11');
    log.record('daily_loss_breach', { dayPnlInr: -3800, limitInr: 3000 });
  }

  function restoredFrom(lines: readonly string[]): ReturnType<DayBook['snapshot']> {
    const book = new DayBook(istEpoch(DAY, '09:20'), 300_000);
    restoreDayBook(book, lines, DAY, { halfSpreadPct: 0, stopSlippagePct: 0 });
    return book.snapshot();
  }

  it('restores the same day from the ledger as from the journal file', async () => {
    const runId = await freshRun();
    const dir = join(journalDir, 'equivalence');
    const clock = { now: istEpoch(DAY, '09:20') };
    const log = new EventLog({ directory: dir, runId, scope: SCOPE, ledger: ledger!, now: () => clock.now });
    writeDay(log, clock);
    await log.flush();
    assert.equal(log.unconfirmedEvents(), 0);

    const fromFile = (await readFile(join(dir, journalFileName(DAY)), 'utf8')).split('\n');
    const fromLedger = await ledger!.dayLines(DAY, SCOPE);
    assert.deepEqual(restoredFrom(fromLedger), restoredFrom(fromFile));

    const snapshot = restoredFrom(fromLedger);
    assert.equal(snapshot.realizedPnlInr, -3800);
    assert.equal(snapshot.tradesToday, 2);
    assert.match(snapshot.killSwitchReason ?? '', /daily loss/);
    assert.match(snapshot.dailyLossBreach ?? '', /daily loss/);
  });

  it('recovers events a crashed process never shipped, by backfilling from its journal', async () => {
    const day = '2026-10-21';
    const dir = join(journalDir, 'crash');
    const crashedRun = await freshRun();
    const clock = { now: istEpoch(day, '09:20') };
    // The ledger rejects every write, as during an outage. The process then dies without a flush.
    const down = { insert: async (): Promise<number> => Promise.reject(new Error('ledger unavailable')) };
    const crashed = new EventLog({
      directory: dir,
      runId: crashedRun,
      scope: SCOPE,
      ledger: down,
      now: () => clock.now,
      onError: () => undefined,
      retryBaseMs: 60_000,
    });
    writeDay(crashed, clock, day);
    await crashed.flush();
    assert.ok(crashed.unconfirmedEvents() > 0, 'the events are queued, not in the ledger');

    const journalLines = (await readFile(join(dir, journalFileName(day)), 'utf8')).split('\n').filter((line) => line.trim() !== '');
    assert.equal(journalLines.length, EVENTS_PER_DAY, 'writeDay produces the expected number of events');
    const report = await backfillDay({ directory: dir, tradingDay: day, ledger: ledger! });
    assert.equal(report.lines, EVENTS_PER_DAY);
    assert.equal(report.inserted, EVENTS_PER_DAY);
    const again = await backfillDay({ directory: dir, tradingDay: day, ledger: ledger! });
    assert.equal(again.inserted, 0, 'a second backfill inserts nothing');
    assert.equal(await ledger!.untaggedDayCount(day), 0, 'every event from this build is tagged');
  });

  it('backfills a journal written before run ids existed, keyed by line number, and reports it as untagged', async () => {
    const day = '2026-10-13';
    await mkdir(join(journalDir, 'legacy'), { recursive: true });
    await writeFile(
      join(journalDir, 'legacy', journalFileName(day)),
      [
        JSON.stringify({ ts: `${day}T09:45:00+05:30`, type: 'entry_submitted', underlying: 'NIFTY' }),
        JSON.stringify({ ts: `${day}T10:00:00+05:30`, type: 'trade_closed', pnlInr: 50 }),
      ].join('\n') + '\n',
    );
    const first = await backfillDay({ directory: join(journalDir, 'legacy'), tradingDay: day, ledger: ledger! });
    assert.equal(first.inserted, 2);
    const second = await backfillDay({ directory: join(journalDir, 'legacy'), tradingDay: day, ledger: ledger! });
    assert.equal(second.inserted, 0);
    const { rows } = await pool!.query<{ n: string }>('SELECT count(*)::text AS n FROM trade_events WHERE source_key LIKE $1', [`legacy:${day}:%`]);
    assert.equal(rows[0]?.n, '2');
    assert.equal(await ledger!.untaggedDayCount(day), 2, 'restore refuses a day with untagged rows');
  });
});

describe('PostgreSQL trading lease', { skip: PG_URL === undefined }, () => {
  const quiet = { setTimer: () => 0, clearTimer: () => undefined };

  it('admits one run at a time, and a new holder waits for expiry plus the margin', async () => {
    const client = `LEASE${suffix}a`;
    const store = new PostgresLeaseStore(pool!);
    const a = new Lease(store, { clientId: client, runId: randomUUID(), ttlMs: 1_000, marginMs: 300, ...quiet });
    const b = new Lease(store, { clientId: client, runId: randomUUID(), ttlMs: 1_000, marginMs: 300, ...quiet });
    assert.equal(await a.acquire(), true);
    assert.equal(await b.acquire(), false);
    await a.release();
    assert.equal(await b.acquire(), false, 'a released lease still waits out the margin');
    await new Promise((resolve) => setTimeout(resolve, 350));
    assert.equal(await b.acquire(), true);
    assert.equal(b.epoch(), 2, 'the epoch advances on every acquisition');
  });

  it('refuses a fenced write once another run has taken the lease, so a stale run cannot add events', async () => {
    const client = `LEASE${suffix}b`;
    const store = new PostgresLeaseStore(pool!);
    const oldRun = randomUUID();
    const newRun = randomUUID();
    await ledger!.startRun({ runId: oldRun, instanceId: 'old', mode: 'live', clientId: client, configFingerprint: 'f', startedAt: new Date().toISOString() });
    const old = new Lease(store, { clientId: client, runId: oldRun, ttlMs: 500, marginMs: 0, ...quiet });
    assert.equal(await old.acquire(), true);
    const fenced = new PostgresLedger(pool!, { clientId: client, runId: oldRun, epoch: () => old.epoch() });
    const row = (seq: number): LedgerRecord => ({
      sourceKey: `${oldRun}:${seq}`,
      runId: oldRun,
      seq,
      tradingDay: '2026-10-22',
      ts: '2026-10-22T10:00:00.000Z',
      eventType: 'trade_closed',
      underlying: 'NIFTY',
      correlationId: undefined,
      record: { type: 'trade_closed', run: oldRun, seq, mode: 'live', client },
    });
    assert.equal(await fenced.insert([row(1)]), 1, 'the holder writes under its lease');

    await new Promise((resolve) => setTimeout(resolve, 600));
    const successor = new Lease(store, { clientId: client, runId: newRun, ttlMs: 5_000, marginMs: 0, ...quiet });
    assert.equal(await successor.acquire(), true);

    await assert.rejects(fenced.insert([row(2)]), LeaseLostError);
    const { rows } = await pool!.query<{ n: string }>('SELECT count(*)::text AS n FROM trade_events WHERE source_key = $1', [`${oldRun}:2`]);
    assert.equal(rows[0]?.n, '0', 'the fenced-out write did not land');
    await successor.release();
  });

  it('refuses a write from a run that never held the lease', async () => {
    const fenced = new PostgresLedger(pool!, { clientId: `LEASE${suffix}c`, runId: randomUUID(), epoch: () => undefined });
    await assert.rejects(
      fenced.insert([
        {
          sourceKey: 'nobody:1',
          runId: undefined,
          seq: undefined,
          tradingDay: '2026-10-22',
          ts: '2026-10-22T10:00:00.000Z',
          eventType: 'x',
          underlying: undefined,
          correlationId: undefined,
          record: { type: 'x' },
        },
      ]),
      LeaseLostError,
    );
  });
});

const REDIS_OPTIONS: RedisOptions = {
  url: REDIS_URL ?? '',
  connectTimeoutMs: 2_000,
  commandTimeoutMs: 2_000,
  onError: () => undefined,
};

describe('Redis rate gate', { skip: REDIS_URL === undefined }, () => {
  it('spaces acquisitions across two processes that share one Redis', async () => {
    const one = await connectRedis(REDIS_OPTIONS);
    const two = await connectRedis(REDIS_OPTIONS);
    try {
      const prefix = `test:${suffix}:rl:`;
      const gateOne = new RedisRateGate(one, { prefix });
      const gateTwo = new RedisRateGate(two, { prefix });
      const window = 300;
      const stamps: number[] = [];
      await gateOne.acquire('chain:NSE', window);
      stamps.push(Date.now());
      await gateTwo.acquire('chain:NSE', window);
      stamps.push(Date.now());
      await gateOne.acquire('chain:NSE', window);
      stamps.push(Date.now());
      for (let i = 1; i < stamps.length; i += 1) {
        const gap = stamps[i]! - stamps[i - 1]!;
        assert.ok(gap >= window - 30, `consecutive acquisitions must be ${window} ms apart, saw ${gap} ms`);
      }
    } finally {
      one.disconnect();
      two.disconnect();
    }
  });
});

describe('Redis cache store', { skip: REDIS_URL === undefined }, () => {
  it('stores JSON with a TTL, returns a miss after expiry, and treats a corrupt entry as a miss', async () => {
    const client = await connectRedis(REDIS_OPTIONS);
    try {
      const cache = new RedisCacheStore(client, `test:${suffix}:cache:`);
      await cache.set('contracts', [{ strike: 24000 }], 5_000);
      assert.deepEqual(await cache.get('contracts'), [{ strike: 24000 }]);
      await cache.set('short', 'x', 150);
      await new Promise((resolve) => setTimeout(resolve, 300));
      assert.equal(await cache.get('short'), undefined);
      await client.set(`test:${suffix}:cache:broken`, '{not json');
      assert.equal(await cache.get('broken'), undefined);
    } finally {
      client.disconnect();
    }
  });
});

describe('connection errors', { skip: REDIS_URL === undefined }, () => {
  it('never echoes the Redis password in a connection failure', async () => {
    const secret = `pw-${suffix}`;
    const url = `redis://:${secret}@127.0.0.1:1/0`;
    await assert.rejects(
      connectRedis({ url, connectTimeoutMs: 500, commandTimeoutMs: 500, onError: () => undefined }),
      (error: Error) => {
        assert.match(error.message, /Redis is not reachable/);
        assert.ok(!error.message.includes(secret), 'the password must not appear in the error');
        return true;
      },
    );
    assert.ok(secretsOf(url).includes(secret), 'the redaction list covers the password');
  });
});

describe('session startup', { skip: PG_URL === undefined || REDIS_URL === undefined }, () => {
  const silent = { info: () => undefined, warn: () => undefined, error: () => undefined };
  const liveConfig = (clientId: string, redisUrl: string) => {
    const url = new URL(PG_URL ?? '');
    url.pathname = `/${DB_NAME}`;
    return loadConfig({
      DHAN_CLIENT_ID: clientId,
      DHAN_ACCESS_TOKEN: 'token',
      MODE: 'live',
      LIVE_TRADING_ACK: LIVE_ACK_PHRASE,
      DATABASE_URL: url.toString(),
      REDIS_URL: redisUrl,
      LEASE_TTL_MS: '5000',
      // The margin after a release is the order timeout. A short one keeps these tests quick.
      ORDER_TIMEOUT_MS: '1000',
    });
  };
  /** A released lease is reacquirable only after the order-timeout margin. */
  const pastMargin = () => new Promise((resolve) => setTimeout(resolve, 1_200));

  it('admits one live run per client, refuses a second, and closes the refused run as failed', async () => {
    const clientId = `TEST${suffix}`;
    const first = await openSession(liveConfig(clientId, REDIS_URL ?? ''), { logger: silent, now: Date.now });
    await assert.rejects(
      openSession(liveConfig(clientId, REDIS_URL ?? ''), { logger: silent, now: Date.now }),
      /another run holds the trading lease/,
    );
    const { rows } = await pool!.query<{ ended_reason: string | null }>('SELECT ended_reason FROM runs WHERE client_id = $1 ORDER BY started_at', [
      clientId,
    ]);
    assert.deepEqual(rows.map((r) => r.ended_reason), [null, 'startup failed'], 'the refused run is closed, the admitted one is open');

    await first.close('stopped');
    await first.close('stopped-again');
    const after = await pool!.query<{ ended_reason: string }>('SELECT ended_reason FROM runs WHERE run_id = $1', [first.runId]);
    assert.equal(after.rows[0]?.ended_reason, 'stopped', 'the first close reason wins');
    await pastMargin();
    const second = await openSession(liveConfig(clientId, REDIS_URL ?? ''), { logger: silent, now: Date.now });
    await second.close('stopped');
  });

  it('refuses to start while an earlier live run never ended, and starts once an operator acknowledges it', async () => {
    const clientId = `CRASH${suffix}`;
    const crashed = await freshRun('live', clientId);
    await assert.rejects(
      openSession(liveConfig(clientId, REDIS_URL ?? ''), { logger: silent, now: Date.now }),
      (error: Error) => {
        assert.match(error.message, /never ended/);
        assert.ok(error.message.includes(crashed), 'the message names the run to review');
        assert.match(error.message, /db:acknowledge/);
        return true;
      },
    );
    assert.equal(await ledger!.acknowledgeRun(crashed, 'flat at the broker, reviewed'), 1);
    await pastMargin();
    const session = await openSession(liveConfig(clientId, REDIS_URL ?? ''), { logger: silent, now: Date.now });
    await session.close('stopped');
  });

  it('refuses to start when Redis is unreachable, and the error carries no password', async () => {
    const secret = `leakcheck-${suffix}`;
    const config = liveConfig(`TEST${suffix}x`, `redis://:${secret}@127.0.0.1:1/0`);
    await assert.rejects(openSession(config, { logger: silent, now: Date.now }), (error: Error) => {
      assert.match(error.message, /persistence startup failed/);
      assert.ok(!error.message.includes(secret));
      return true;
    });
  });
});
