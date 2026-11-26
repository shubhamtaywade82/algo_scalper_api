import { strict as assert } from 'node:assert';
import { randomBytes } from 'node:crypto';
import { describe, it } from 'node:test';
import { configFingerprint, loadConfig } from '../src/config.js';
import { MemoryCacheStore, msUntilNextIstMidnight } from '../src/persistence/cache.js';
import { parseJournal } from '../src/persistence/backfill.js';
import { Lease, MemoryLeaseStore } from '../src/persistence/lease.js';
import { MemoryRateGate } from '../src/persistence/rateGate.js';
import { errorMessage, redact, secretsOf } from '../src/persistence/redact.js';
import { parseRedisUrl, validatePostgresUrl } from '../src/persistence/urls.js';
import { scopeJournalLines } from '../src/persistence/scope.js';
import { istEpoch } from './support/fixtures.js';

const BASE = { DHAN_CLIENT_ID: '1100000001', DHAN_ACCESS_TOKEN: 'token', DATABASE_URL: 'postgres://paper.test.invalid/agent' };
const RUN = '6f1c2d3e-4a5b-4c6d-8e7f-900112233445';

describe('redact', () => {
  // A fresh secret per run. The tests check it never leaks, so no credential-shaped literal is committed.
  const SECRET = randomBytes(9).toString('hex');

  it('removes the password from a connection string echoed in free text', () => {
    const text = `connect failed for postgres://agent:${SECRET}@db.internal:5432/ledger`;
    assert.equal(redact(text), 'connect failed for postgres://***@db.internal:5432/ledger');
    assert.ok(!redact(text).includes(SECRET));
  });

  it('removes a password that appears on its own, even when it is not in a URL', () => {
    assert.equal(redact(`auth failed: ${SECRET}`, [SECRET]), 'auth failed: ***');
  });

  it('builds an error message that carries neither the URL nor its password, and is bounded', () => {
    const url = `redis://:${SECRET}@cache.internal:6379/0`;
    const message = errorMessage(new Error(`could not reach ${url} with ${SECRET}`), secretsOf(url));
    assert.ok(!message.includes(SECRET));
    assert.ok(message.length <= 300);
  });
});

describe('persistence URLs', () => {
  it('parses a TLS Redis URL with credentials and a database index', () => {
    // The expected password is built per run. Its '@' is percent-encoded in the URL, so the parser must decode it.
    const expected = `p@${randomBytes(4).toString('hex')}`;
    assert.deepEqual(parseRedisUrl(`rediss://agent:${encodeURIComponent(expected)}@cache.internal:6380/3`), {
      host: 'cache.internal',
      port: 6380,
      username: 'agent',
      password: expected,
      db: 3,
      tls: true,
    });
  });

  it('defaults the Redis port and database', () => {
    assert.deepEqual(
      { port: parseRedisUrl('redis://127.0.0.1').port, db: parseRedisUrl('redis://127.0.0.1').db },
      { port: 6379, db: 0 },
    );
  });

  it('rejects the wrong scheme without echoing the URL', () => {
    assert.throws(() => parseRedisUrl('http://cache:secret@x'), (error: Error) => {
      assert.match(error.message, /redis:\/\/ or rediss:\/\//);
      assert.ok(!error.message.includes('secret'));
      return true;
    });
    assert.throws(() => validatePostgresUrl('mysql://u:p@h/db'), /postgres:\/\/ or postgresql:\/\//);
    assert.throws(() => validatePostgresUrl('not a url'), /DATABASE_URL is not a valid URL/);
  });
});

describe('config persistence rules', () => {
  it('requires the ledger and the leader lock in live mode', () => {
    assert.throws(() => loadConfig({ ...BASE, MODE: 'live', LIVE_TRADING_ACK: 'I_ACCEPT_LIVE_ORDER_RISK' }), /DATABASE_URL.*REDIS_URL/);
    assert.throws(
      () =>
        loadConfig({
          ...BASE,
          MODE: 'live',
          LIVE_TRADING_ACK: 'I_ACCEPT_LIVE_ORDER_RISK',
          DATABASE_URL: 'postgres://u:p@h/db',
        }),
      /REDIS_URL/,
    );
  });

  it('requires the PostgreSQL store in paper mode, because the paper wallet and positions live there', () => {
    assert.throws(() => loadConfig({ DHAN_CLIENT_ID: '1', DHAN_ACCESS_TOKEN: 't' }), /paper mode requires DATABASE_URL/);
    const config = loadConfig(BASE);
    assert.equal(config.persistence.databaseUrl, 'postgres://paper.test.invalid/agent');
    assert.equal(config.persistence.redisUrl, undefined, 'Redis is optional in paper mode');
    assert.equal(config.persistence.leaseTtlMs, 30_000);
  });

  it('fingerprints the trading configuration and never a secret or connection string', () => {
    const plain = loadConfig(BASE);
    const withSecrets = loadConfig({
      DHAN_CLIENT_ID: BASE.DHAN_CLIENT_ID,
      DHAN_PIN: '4321',
      DHAN_TOTP_SECRET: 'JBSWY3DPEHPK3PXP',
      DATABASE_URL: 'postgres://u:topsecret@db/ledger',
      REDIS_URL: 'redis://:topsecret@cache/0',
      OLLAMA_API_KEY: 'topsecret',
    });
    assert.equal(configFingerprint(plain), configFingerprint(withSecrets), 'neither secrets nor the auth mode change the fingerprint');
    assert.notEqual(configFingerprint(plain), configFingerprint(loadConfig({ ...BASE, CAPITAL_INR: '500000' })));
    assert.match(configFingerprint(plain), /^[0-9a-f]{64}$/);
  });

  it('rejects an invalid leader lock ttl', () => {
    assert.throws(() => loadConfig({ ...BASE, LEASE_TTL_MS: '100' }), /LEASE_TTL_MS/);
  });
});

describe('parseJournal', () => {
  const DAY = '2026-10-12';
  const line = (ts: string, type: string, extra: Record<string, unknown> = {}) => JSON.stringify({ ts, type, ...extra });
  const T = (hhmm: string) => `${DAY}T${hhmm}:00+05:30`;

  it('keys lines from this build by run and sequence, and legacy lines by physical line number', () => {
    const text = [
      line(T('09:45'), 'legacy_event'),
      '',
      JSON.stringify({ ts: T('10:00'), type: 'entry_submitted', run: RUN, seq: 1, underlying: 'NIFTY', correlationId: 'ENT-1' }),
    ].join('\n');
    const rows = parseJournal(text, DAY);
    assert.deepEqual(
      rows.map((row) => row.sourceKey),
      [`legacy:${DAY}:1`, `${RUN}:1`],
    );
    assert.equal(rows[1]?.runId, RUN);
    assert.equal(rows[1]?.correlationId, 'ENT-1');
    assert.equal(rows[0]?.runId, undefined);
  });

  it('refuses a malformed line, naming only its number', () => {
    assert.throws(() => parseJournal(`${line(T('09:45'), 'ok')}\n{"ts":`, DAY), /journal line 2 is malformed/);
  });

  it('refuses a line from another trading day, a partial run field, and a run id that is not a UUID', () => {
    assert.throws(() => parseJournal(line('2026-10-13T09:45:00+05:30', 'x'), DAY), /another trading day/);
    assert.throws(
      () => parseJournal(JSON.stringify({ ts: T('09:45'), type: 'x', run: RUN }), DAY),
      /partial run or seq/,
    );
    assert.throws(
      () => parseJournal(JSON.stringify({ ts: T('09:45'), type: 'x', run: 'not-a-uuid', seq: 1 }), DAY),
      /not a UUID/,
    );
  });
});

describe('Lease', () => {
  const CLIENT = '1100000001';

  function fixture(ttlMs = 900, marginMs = 200) {
    let clock = 0;
    const now = () => clock;
    const store = new MemoryLeaseStore(now);
    const base = { clientId: CLIENT, ttlMs, marginMs, now, setTimer: () => 0, clearTimer: () => undefined };
    return {
      store,
      run: (runId: string) => new Lease(store, { ...base, runId }),
      advance: (ms: number) => {
        clock += ms;
      },
    };
  }

  it('admits one run at a time, and a new holder waits for expiry plus the margin', async () => {
    const f = fixture(900, 200);
    const a = f.run('run-a');
    const b = f.run('run-b');
    assert.equal(await a.acquire(), true);
    assert.equal(await b.acquire(), false);
    f.advance(900);
    assert.equal(await b.acquire(), false, 'expiry alone is not enough: the margin must pass as well');
    f.advance(200);
    assert.equal(await b.acquire(), true);
    assert.equal(b.epoch(), 2, 'every acquisition advances the epoch');
  });

  it('keeps the lease while renewals succeed, and stops holding it after a full ttl of silence', async () => {
    let clock = 0;
    const now = () => clock;
    const store = new MemoryLeaseStore(now);
    let reachable = true;
    const flaky = {
      acquire: (c: string, r: string, t: number, m: number) => store.acquire(c, r, t, m),
      renew: async (c: string, r: string, e: number, t: number) => {
        if (!reachable) {
          throw new Error('connection reset');
        }
        return store.renew(c, r, e, t);
      },
      release: (c: string, r: string, e: number, handoff: boolean, margin: number) => store.release(c, r, e, handoff, margin),
    };
    const lease = new Lease(flaky, {
      clientId: CLIENT,
      runId: 'run-a',
      ttlMs: 900,
      marginMs: 200,
      now,
      setTimer: () => 0,
      clearTimer: () => undefined,
    });
    const lost: string[] = [];
    lease.onLost((reason) => lost.push(reason));
    assert.equal(await lease.acquire(), true);

    for (let i = 0; i < 4; i += 1) {
      clock += 300;
      await lease.renewTick();
      assert.equal(lease.holds(), true, 'renewals inside the ttl keep the lease');
    }

    reachable = false;
    clock += 300;
    await lease.renewTick();
    assert.equal(lease.holds(), true, 'a failed renewal inside the ttl is retried, not treated as a loss');
    assert.equal(lost.length, 0);

    clock += 700;
    await lease.renewTick();
    assert.equal(lease.holds(), false, 'a lease that could not be renewed for a full ttl is not held');
    assert.equal(lease.epoch(), undefined);
    assert.equal(lost.length, 1);
    assert.match(lost[0] ?? '', /could not be renewed/);
  });

  it('is lost when another run has taken the lease after expiry, and the old run may not write under its epoch', async () => {
    const f = fixture(900, 200);
    const a = f.run('run-a');
    await a.acquire();
    const lost: string[] = [];
    a.onLost((reason) => lost.push(reason));
    f.advance(1_100);
    const b = f.run('run-b');
    assert.equal(await b.acquire(), true);
    await a.renewTick();
    assert.equal(a.holds(), false);
    assert.equal(a.epoch(), undefined, 'a lost lease has no epoch to write under');
    assert.match(lost[0] ?? '', /held by another run|expired/);
  });

  it('takes the lease back after a loss once it is free, and leaves it to a run that took over', async () => {
    let clock = 0;
    const now = () => clock;
    const store = new MemoryLeaseStore(now);
    const timers: (() => void)[] = [];
    const options = { clientId: CLIENT, ttlMs: 900, marginMs: 200, now, setTimer: (fn: () => void) => timers.push(fn), clearTimer: () => undefined };
    const a = new Lease(store, { ...options, runId: 'run-a' });
    let reacquired = 0;
    a.reacquireAfterLoss(300, () => { reacquired += 1; });
    await a.acquire();

    clock += 1_000;
    await a.renewTick();
    assert.equal(a.holds(), false, 'the lease expired, so it is lost');
    const retry = timers.at(-1)!;
    retry();
    await new Promise((resolve) => setImmediate(resolve));
    assert.equal(reacquired, 0, 'not before expiry plus the margin');

    clock += 200;
    retry();
    await new Promise((resolve) => setImmediate(resolve));
    assert.equal(reacquired, 1);
    assert.equal(a.holds(), true);
    assert.equal(a.epoch(), 2, 'a new epoch fences writes from before the loss');

    clock += 1_200;
    const b = new Lease(store, { ...options, runId: 'run-b' });
    await a.renewTick();
    assert.equal(await b.acquire(), true, 'once lost again, another run can take it');
    timers.at(-2)?.();
    await new Promise((resolve) => setImmediate(resolve));
    assert.equal(reacquired, 1, 'a run that took over keeps it');
  });

  it('lets the next holder acquire at once after an immediate handoff release', async () => {
    const f = fixture(900, 200);
    const a = f.run('run-a');
    await a.acquire();
    await a.release(true);
    assert.equal(await f.run('run-b').acquire(), true);
  });

  it('releases the lease for the next holder only after the margin', async () => {
    const f = fixture(900, 200);
    const a = f.run('run-a');
    await a.acquire();
    await a.release();
    assert.equal(a.holds(), false);
    assert.equal(await f.run('run-b').acquire(), false, 'the margin protects an order that may still be in flight');
    f.advance(200);
    assert.equal(await f.run('run-b').acquire(), true);
  });
});

describe('MemoryRateGate', () => {
  it('spaces acquisitions under one key by the window and leaves other keys alone', async () => {
    let clock = 0;
    const waits: number[] = [];
    const gate = new MemoryRateGate({
      now: () => clock,
      sleep: async (ms) => {
        waits.push(ms);
        clock += ms;
      },
    });
    await gate.acquire('chain:NSE', 3_000);
    await gate.acquire('chain:NSE', 3_000);
    await gate.acquire('chain:BSE', 3_000);
    assert.deepEqual(waits, [3_000], 'only the second NSE call waits, and BSE does not');
  });
});

describe('MemoryCacheStore', () => {
  it('expires entries at their TTL and returns a miss afterwards', async () => {
    let clock = 0;
    const cache = new MemoryCacheStore(() => clock);
    await cache.set('contracts', { count: 3 }, 1_000);
    assert.deepEqual(await cache.get('contracts'), { count: 3 });
    clock = 1_000;
    assert.equal(await cache.get('contracts'), undefined);
  });
});

describe('msUntilNextIstMidnight', () => {
  it('counts down to the next IST midnight, not UTC midnight', () => {
    const at = istEpoch('2026-10-12', '23:00');
    assert.equal(msUntilNextIstMidnight(at), 60 * 60 * 1000);
  });
});

describe('scopeJournalLines', () => {
  const DAY = '2026-10-12';
  const paper = { mode: 'paper', clientId: '1100000001' };
  const tagged = (mode: string, client: string, type: string) =>
    JSON.stringify({ ts: `${DAY}T09:45:00+05:30`, type, mode, client });

  it('keeps only the lines written by this mode and client', () => {
    const text = [tagged('paper', '1100000001', 'a'), tagged('live', '1100000001', 'b'), tagged('paper', '2200000002', 'c'), ''].join('\n');
    const kept = scopeJournalLines(text, paper, DAY).map((line) => JSON.parse(line).type);
    assert.deepEqual(kept, ['a']);
  });

  it('refuses a journal with untagged lines, because they cannot be attributed to a mode', () => {
    const text = [tagged('paper', '1100000001', 'a'), JSON.stringify({ ts: `${DAY}T09:46:00+05:30`, type: 'legacy' })].join('\n');
    assert.throws(() => scopeJournalLines(text, paper, DAY), /predate mode and client tags/);
  });

  it('refuses a malformed line and names its number', () => {
    assert.throws(() => scopeJournalLines(`${tagged('paper', '1100000001', 'a')}\n{"ts":`, paper, DAY), /journal line 2 is malformed/);
  });
});
