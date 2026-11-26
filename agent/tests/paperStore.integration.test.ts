import { strict as assert } from 'node:assert';
import { randomUUID } from 'node:crypto';
import { after, before, describe, it } from 'node:test';
import type { Pool } from 'pg';
import { loadConfig } from '../src/config.js';
import { PostgresPaperExecutionPort } from '../src/execution/postgresPaper.js';
import { PostgresPaperStore, type PaperOrderRecord, type PaperPositionRecord } from '../src/execution/paperStore.js';
import { LeaseLostError, PostgresLeaseStore } from '../src/persistence/lease.js';
import type { LedgerFence } from '../src/persistence/ledger.js';
import { MIGRATIONS } from '../src/persistence/migrations.js';
import { createPostgresPool, migrate } from '../src/persistence/postgres.js';
import { openSession } from '../src/persistence/session.js';
import { createConsoleLogger } from '../src/ops/logger.js';
import { contract, istEpoch } from './support/fixtures.js';

/**
 * Integration tests for the PostgreSQL paper venue against a real database. Skipped unless TEST_DATABASE_URL is set.
 * Each test uses its own client id, so runs never see each other's wallets or positions.
 */
const PG_URL = process.env['TEST_DATABASE_URL'];
const NOW = istEpoch('2026-10-12', '10:00');
const SILENT = createConsoleLogger(() => undefined, () => NOW);

describe('PostgreSQL paper store', { skip: PG_URL === undefined }, () => {
  let pool: Pool;
  let counter = 0;

  before(async () => {
    pool = createPostgresPool({ url: PG_URL!, maxConnections: 4, connectTimeoutMs: 5_000, statementTimeoutMs: 10_000, onError: () => undefined });
    await migrate(pool, MIGRATIONS);
  });

  after(async () => {
    await pool.end();
  });

  /** A fresh client with its own leased account, so the fence is real and the lease belongs to this test only. */
  async function leasedFence(): Promise<{ clientId: string; fence: LedgerFence; release: () => Promise<void> }> {
    counter += 1;
    const clientId = `PAPER-${randomUUID().slice(0, 8)}-${counter}`;
    const runId = randomUUID();
    const account = `paper:${clientId}`;
    const leases = new PostgresLeaseStore(pool);
    const epoch = await leases.acquire(account, runId, 60_000, 0);
    assert.ok(epoch !== undefined, 'the test account is free');
    return {
      clientId,
      fence: { clientId: account, runId, epoch: () => epoch },
      release: () => leases.release(account, runId, epoch!, false, 0),
    };
  }

  function position(clientId: string, id: string): PaperPositionRecord {
    return {
      positionId: id,
      clientId,
      underlying: 'NIFTY',
      securityId: '48001',
      exchangeSegment: 'NSE_FNO',
      tickSize: 0.05,
      quantity: 75,
      averagePrice: 100,
      stopLossPrice: 70,
      targetPrice: 160,
      openedAt: NOW,
    };
  }

  function order(id: string, positionId: string, kind: PaperOrderRecord['kind'], side: PaperOrderRecord['side'], price: number): PaperOrderRecord {
    return { correlationId: id, positionId, kind, side, quantity: 75, price, reason: undefined, at: NOW };
  }

  it('creates the wallet once, and refuses a different starting capital for an existing wallet', async () => {
    const { clientId, fence } = await leasedFence();
    const store = new PostgresPaperStore(pool, fence);
    await store.ensureWallet(clientId, 250_000);
    await store.ensureWallet(clientId, 250_000);
    assert.equal(await store.balance(clientId), 250_000);
    await assert.rejects(store.ensureWallet(clientId, 300_000), /started with 250000 INR; CAPITAL_INR is 300000/);
  });

  it('records an entry and its close, and the wallet and P&L agree with the cash moved', async () => {
    const { clientId, fence } = await leasedFence();
    const store = new PostgresPaperStore(pool, fence);
    await store.ensureWallet(clientId, 100_000);
    const id = `${clientId}-ENT`;
    assert.equal(
      await store.openPosition({ position: position(clientId, id), order: order(id, id, 'ENTRY', 'BUY', 100), debitInr: 7_500 }),
      'OPENED',
    );
    assert.equal(await store.balance(clientId), 92_500);
    assert.equal((await store.openPositions(clientId)).length, 1);

    const outcome = await store.closePosition({
      clientId,
      positionId: id,
      order: order(`${id}-X`, id, 'EXIT', 'SELL', 120),
      creditInr: 9_000,
      exitPrice: 120,
      exitReason: 'MANUAL',
      realizedPnlInr: 1_500,
      at: NOW,
    });
    assert.equal(outcome, 'CLOSED');
    assert.equal(await store.balance(clientId), 101_500);
    assert.equal((await store.openPositions(clientId)).length, 0);
  });

  it('refuses an entry the wallet cannot pay for, and writes nothing for it', async () => {
    const { clientId, fence } = await leasedFence();
    const store = new PostgresPaperStore(pool, fence);
    await store.ensureWallet(clientId, 1_000);
    const id = `${clientId}-BIG`;
    assert.equal(
      await store.openPosition({ position: position(clientId, id), order: order(id, id, 'ENTRY', 'BUY', 100), debitInr: 7_500 }),
      'INSUFFICIENT_CASH',
    );
    assert.equal(await store.balance(clientId), 1_000);
    const { rows } = await pool.query('SELECT 1 FROM paper_positions WHERE position_id = $1', [id]);
    assert.equal(rows.length, 0);
  });

  it('never closes a position twice, and the database refuses to reopen or edit a closed one', async () => {
    const { clientId, fence } = await leasedFence();
    const store = new PostgresPaperStore(pool, fence);
    await store.ensureWallet(clientId, 100_000);
    const id = `${clientId}-ONCE`;
    await store.openPosition({ position: position(clientId, id), order: order(id, id, 'ENTRY', 'BUY', 100), debitInr: 7_500 });
    const close = {
      clientId,
      positionId: id,
      order: order(`${id}-X`, id, 'EXIT', 'SELL', 100),
      creditInr: 7_500,
      exitPrice: 100,
      exitReason: 'MANUAL',
      realizedPnlInr: 0,
      at: NOW,
    };
    assert.equal(await store.closePosition(close), 'CLOSED');
    assert.equal(await store.closePosition({ ...close, order: order(`${id}-Y`, id, 'EXIT', 'SELL', 100) }), 'NOT_OPEN');
    await assert.rejects(pool.query("UPDATE paper_positions SET status = 'OPEN', closed_at = NULL WHERE position_id = $1", [id]), /already closed/);
    assert.equal(await store.balance(clientId), 100_000, 'the second close credited nothing');
  });

  it('keeps orders and cash entries append-only, even for the table owner', async () => {
    const { clientId, fence } = await leasedFence();
    const store = new PostgresPaperStore(pool, fence);
    await store.ensureWallet(clientId, 100_000);
    const id = `${clientId}-HIST`;
    await store.openPosition({ position: position(clientId, id), order: order(id, id, 'ENTRY', 'BUY', 100), debitInr: 7_500 });
    await assert.rejects(pool.query('UPDATE paper_orders SET price = 1 WHERE correlation_id = $1', [id]), /append-only/);
    await assert.rejects(pool.query('DELETE FROM paper_wallet_entries WHERE correlation_id = $1', [id]), /append-only/);
  });

  it('refuses every write once the lease is released, so a stale run cannot move paper cash', async () => {
    const { clientId, fence, release } = await leasedFence();
    const store = new PostgresPaperStore(pool, fence);
    await store.ensureWallet(clientId, 100_000);
    await release();
    const id = `${clientId}-LOST`;
    await assert.rejects(
      store.openPosition({ position: position(clientId, id), order: order(id, id, 'ENTRY', 'BUY', 100), debitInr: 7_500 }),
      LeaseLostError,
    );
    assert.equal(await store.balance(clientId), 100_000);
  });

  it('restores the venue with the same cash and open positions after a restart', async () => {
    const { clientId, fence } = await leasedFence();
    const store = new PostgresPaperStore(pool, fence);
    const first = new PostgresPaperExecutionPort(store, { clientId, slippageBps: 0, initialCapitalInr: 100_000, logger: SILENT, now: () => NOW });
    await first.open();
    await first.submitEntry({
      side: 'BUY',
      correlationId: `${clientId}-RESTART`,
      underlying: 'NIFTY',
      contract: contract({ optionType: 'CE', strike: 22_450, securityId: '48001' }),
      quantity: 75,
      entryReference: 100,
      stopLossPrice: 70,
      targetPrice: 160,
    });
    const second = new PostgresPaperExecutionPort(store, { clientId, slippageBps: 0, initialCapitalInr: 100_000, logger: SILENT, now: () => NOW });
    await second.open();
    assert.equal(second.openPositionCount(), 1);
    assert.equal(await second.cash(), 100_000 - 100 * 75);
  });

  it('gives a second paper run for the same client a refusal, not a second trading right', async () => {
    const clientId = `PAPER-SESSION-${randomUUID().slice(0, 8)}`;
    const config = loadConfig({
      MODE: 'paper',
      DHAN_CLIENT_ID: clientId,
      DHAN_ACCESS_TOKEN: 'token',
      DATABASE_URL: PG_URL!,
      ORDER_TIMEOUT_MS: '1000',
    });
    const first = await openSession(config, { logger: SILENT, now: () => Date.now() });
    try {
      assert.ok(first.pool !== undefined && first.fence !== undefined, 'the paper venue gets the pool and the fence');
      await assert.rejects(openSession(config, { logger: SILENT, now: () => Date.now() }), /another run holds the trading lease for paper:/);
    } finally {
      await first.close('test finished');
    }
  });
});
