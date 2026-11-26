import { strict as assert } from 'node:assert';
import { mkdtemp, readFile, readdir, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { after, before, describe, it } from 'node:test';
import type { LedgerRecord } from '../src/persistence/ledger.js';
import { EventLog, journalFileName, type LedgerWriter } from '../src/ops/eventLog.js';
import { istEpoch } from './support/fixtures.js';

const RUN = '6f1c2d3e-4a5b-4c6d-8e7f-900112233445';
const SCOPE = { mode: 'paper' as const, clientId: 'TEST' };

let directory = '';

before(async () => {
  directory = await mkdtemp(join(tmpdir(), 'journal-test-'));
});

after(async () => {
  await rm(directory, { recursive: true, force: true });
});

/** A ledger fake that keeps rows and can be told to fail a number of calls. */
function fakeLedger(failures = 0): LedgerWriter & { rows: LedgerRecord[]; calls: number } {
  let remaining = failures;
  const ledger = {
    rows: [] as LedgerRecord[],
    calls: 0,
    async insert(records: readonly LedgerRecord[]): Promise<number> {
      ledger.calls += 1;
      if (remaining > 0) {
        remaining -= 1;
        throw new Error('ledger unavailable');
      }
      const known = new Set(ledger.rows.map((row) => row.sourceKey));
      const fresh = records.filter((row) => !known.has(row.sourceKey));
      ledger.rows.push(...fresh);
      return fresh.length;
    },
  };
  return ledger;
}

describe('EventLog daily journal', () => {
  it('routes each record to the file for its own IST trading day', async () => {
    let clock = istEpoch('2026-10-12', '15:20');
    const errors: unknown[] = [];
    const log = new EventLog({ directory: join(directory, 'rotate'), runId: RUN, scope: SCOPE, onError: (e) => errors.push(e), now: () => clock });
    log.record('trade_closed', { underlying: 'NIFTY', pnlInr: 100 });
    clock = istEpoch('2026-10-13', '09:30');
    log.record('entry_submitted', { underlying: 'NIFTY' });
    await log.flush();

    assert.deepEqual(errors, []);
    const files = (await readdir(join(directory, 'rotate'))).sort();
    assert.deepEqual(files, [journalFileName('2026-10-12'), journalFileName('2026-10-13')]);
    const first = (await readFile(join(directory, 'rotate', journalFileName('2026-10-12')), 'utf8')).trim().split('\n');
    assert.equal(first.length, 1);
    assert.equal(JSON.parse(first[0] ?? '{}').type, 'trade_closed');
  });

  it('stamps every line with the run id and a per-run sequence number', async () => {
    const clock = istEpoch('2026-10-14', '10:00');
    const log = new EventLog({ directory: join(directory, 'seq'), runId: RUN, scope: SCOPE, now: () => clock });
    log.record('first', {});
    log.record('second', {});
    await log.flush();
    const lines = (await readFile(join(directory, 'seq', journalFileName('2026-10-14')), 'utf8')).trim().split('\n');
    assert.deepEqual(
      lines.map((line) => [JSON.parse(line).run, JSON.parse(line).seq]),
      [
        [RUN, 1],
        [RUN, 2],
      ],
    );
  });

  it('hands every recorded and durable event to onEvent, for operator alerts', async () => {
    const clock = istEpoch('2026-10-14', '10:00');
    const seen: string[] = [];
    const log = new EventLog({ directory: join(directory, 'hook'), runId: RUN, scope: SCOPE, now: () => clock, onEvent: (type) => seen.push(type) });
    log.record('halted', { underlying: 'NIFTY' });
    await log.durable('daily_loss_breach', { dayPnlInr: -1 });
    await log.flush();
    assert.deepEqual(seen, ['halted', 'daily_loss_breach']);
  });

  it('creates the directory on first write and keeps lines whole under concurrent records', async () => {
    const clock = istEpoch('2026-10-14', '10:00');
    const log = new EventLog({ directory: join(directory, 'nested', 'deeper'), runId: RUN, scope: SCOPE, now: () => clock });
    for (let i = 0; i < 50; i += 1) {
      log.record('tick', { i });
    }
    await log.flush();
    const lines = (await readFile(join(directory, 'nested', 'deeper', journalFileName('2026-10-14')), 'utf8'))
      .trim()
      .split('\n');
    assert.equal(lines.length, 50);
    assert.ok(lines.every((line) => JSON.parse(line).type === 'tick'));
  });

  it('reports a failed record write to onError and keeps accepting records', async () => {
    const clock = istEpoch('2026-10-15', '10:00');
    const errors: unknown[] = [];
    // A regular file where the directory should be makes mkdir fail.
    const blocker = join(directory, 'blocker');
    await writeFile(blocker, 'x');
    const log = new EventLog({ directory: join(blocker, 'journal'), runId: RUN, scope: SCOPE, onError: (e) => errors.push(e), now: () => clock });
    log.record('first', {});
    log.record('second', {});
    await log.flush();
    assert.equal(errors.length, 2, 'each failed record is reported, none is silently dropped');
  });
});

describe('EventLog durable writes', () => {
  it('resolves only after the line is in the journal and in the ledger', async () => {
    const clock = istEpoch('2026-10-16', '09:50');
    const ledger = fakeLedger();
    const log = new EventLog({ directory: join(directory, 'durable'), runId: RUN, scope: SCOPE, ledger, now: () => clock });
    await log.durable('entry_submitted', { underlying: 'NIFTY', correlationId: 'ENT-1' });

    const lines = (await readFile(join(directory, 'durable', journalFileName('2026-10-16')), 'utf8')).trim().split('\n');
    assert.equal(lines.length, 1);
    assert.equal(ledger.rows.length, 1);
    assert.equal(ledger.rows[0]?.sourceKey, `${RUN}:1`);
    assert.equal(ledger.rows[0]?.correlationId, 'ENT-1');
  });

  it('rejects when the ledger refuses the write, so the caller can refuse to act', async () => {
    const clock = istEpoch('2026-10-16', '09:55');
    const log = new EventLog({ directory: join(directory, 'durable'), runId: RUN, scope: SCOPE, ledger: fakeLedger(1), now: () => clock });
    await assert.rejects(log.durable('entry_submitted', { underlying: 'NIFTY' }), /ledger unavailable/);
  });

  it('rejects when the journal cannot be written', async () => {
    const clock = istEpoch('2026-10-16', '10:00');
    const blocker = join(directory, 'durable-blocker');
    await writeFile(blocker, 'x');
    const log = new EventLog({ directory: join(blocker, 'journal'), runId: RUN, scope: SCOPE, now: () => clock });
    await assert.rejects(log.durable('entry_submitted', {}));
  });

  it('works in journal-only mode, where durable means fsynced to the file', async () => {
    const clock = istEpoch('2026-10-16', '10:05');
    const log = new EventLog({ directory: join(directory, 'journal-only'), runId: RUN, scope: SCOPE, now: () => clock });
    await log.durable('exit_submitted', { underlying: 'NIFTY' });
    const text = await readFile(join(directory, 'journal-only', journalFileName('2026-10-16')), 'utf8');
    assert.equal(JSON.parse(text.trim()).type, 'exit_submitted');
  });
});

describe('EventLog ledger outbox', () => {
  it('ships recorded events to the ledger, in order, on flush', async () => {
    const clock = istEpoch('2026-10-17', '11:00');
    const ledger = fakeLedger();
    const log = new EventLog({ directory: join(directory, 'outbox'), runId: RUN, scope: SCOPE, ledger, now: () => clock });
    log.record('signal_detected', { underlying: 'NIFTY' });
    log.record('signal_dropped', { underlying: 'NIFTY' });
    await log.flush();
    assert.deepEqual(
      ledger.rows.map((row) => row.eventType),
      ['signal_detected', 'signal_dropped'],
    );
    assert.equal(log.unconfirmedEvents(), 0);
  });

  it('keeps events queued through a ledger outage and delivers them once it recovers', async () => {
    const clock = istEpoch('2026-10-17', '11:05');
    const errors: unknown[] = [];
    const ledger = fakeLedger(2);
    const log = new EventLog({
      directory: join(directory, 'outage'),
      runId: RUN, scope: SCOPE,
      ledger,
      now: () => clock,
      onError: (e) => errors.push(e),
      retryBaseMs: 1,
      retryMaxMs: 2,
    });
    log.record('halted', { underlying: 'NIFTY' });
    for (let i = 0; i < 50 && ledger.rows.length === 0; i += 1) {
      await new Promise((resolve) => setTimeout(resolve, 5));
      await log.flush();
    }
    assert.equal(ledger.rows.length, 1, 'the queued event is delivered after the outage');
    assert.equal(errors.length, 2, 'each failed attempt is reported');
    assert.equal(log.unconfirmedEvents(), 0);
  });

  it('bounds the queue during a long outage, reports the overflow once, and keeps writing the journal', async () => {
    const clock = istEpoch('2026-10-17', '11:10');
    const errors: unknown[] = [];
    const ledger = fakeLedger(Number.MAX_SAFE_INTEGER);
    const log = new EventLog({
      directory: join(directory, 'overflow'),
      runId: RUN, scope: SCOPE,
      ledger,
      now: () => clock,
      onError: (e) => errors.push(e),
      maxOutbox: 3,
      retryBaseMs: 60_000,
    });
    for (let i = 0; i < 6; i += 1) {
      log.record('tick_event', { i });
    }
    await log.flush();
    assert.equal(log.unconfirmedEvents(), 6, 'queued plus overflowed events are all counted as not in the ledger');
    const overflowReports = errors.filter((error) => String(error).includes('outbox is full'));
    assert.equal(overflowReports.length, 1, 'overflow is reported once, not once per event');
    const journalLines = (await readFile(join(directory, 'overflow', journalFileName('2026-10-17')), 'utf8')).trim().split('\n');
    assert.equal(journalLines.length, 6, 'the journal keeps every event even when the outbox overflows');
  });
});
