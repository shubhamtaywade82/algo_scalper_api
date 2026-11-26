import { strict as assert } from 'node:assert';
import { describe, it } from 'node:test';
import { PostgresPaperExecutionPort } from '../src/execution/postgresPaper.js';
import {
  toPaise,
  type CloseResult,
  type OpenEntryResult,
  type PaperOrderRecord,
  type PaperPositionRecord,
  type PaperStore,
} from '../src/execution/paperStore.js';
import type { EntryOrder, ExecutionEvent, ExitOrder } from '../src/execution/ports.js';
import { createConsoleLogger } from '../src/ops/logger.js';
import { roundTripChargesInr } from '../src/options/pricing.js';
import { contract, istEpoch } from './support/fixtures.js';

const NOW = istEpoch('2026-10-12', '10:00');
const OPTION = contract({ optionType: 'CE', strike: 22_450, securityId: '48001' });
const CLIENT = '1100000001';
const SILENT = createConsoleLogger(() => undefined, () => NOW);

/**
 * An in-memory PaperStore with the same rules as the PostgreSQL one: a closed position cannot close again, a
 * duplicate id is refused, and cash cannot go negative. `failNext` makes the next call throw, to model a lost write.
 */
class MemoryPaperStore implements PaperStore {
  wallet: number | undefined;
  readonly positions = new Map<string, PaperPositionRecord & { status: 'OPEN' | 'CLOSED'; pnl?: number }>();
  readonly orders: PaperOrderRecord[] = [];
  failNext: string | undefined;

  private maybeFail(method: string): void {
    if (this.failNext === method) {
      this.failNext = undefined;
      throw new Error(`simulated database failure in ${method}`);
    }
  }

  async ensureWallet(_clientId: string, initialInr: number): Promise<void> {
    this.maybeFail('ensureWallet');
    this.wallet ??= toPaise(initialInr);
  }

  async balance(): Promise<number> {
    if (this.wallet === undefined) {
      throw new Error('no wallet');
    }
    return this.wallet;
  }

  async openPositions(): Promise<PaperPositionRecord[]> {
    return [...this.positions.values()].filter((p) => p.status === 'OPEN');
  }

  async openPosition(input: { position: PaperPositionRecord; order: PaperOrderRecord; debitInr: number }): Promise<OpenEntryResult> {
    this.maybeFail('openPosition');
    if (this.wallet === undefined) {
      throw new Error('no wallet');
    }
    if (this.positions.has(input.position.positionId)) {
      return 'DUPLICATE';
    }
    if (this.wallet < input.debitInr) {
      return 'INSUFFICIENT_CASH';
    }
    this.wallet = toPaise(this.wallet - input.debitInr);
    this.positions.set(input.position.positionId, { ...input.position, status: 'OPEN' });
    this.orders.push(input.order);
    return 'OPENED';
  }

  async closePosition(input: {
    positionId: string;
    order: PaperOrderRecord;
    creditInr: number;
    realizedPnlInr: number;
  }): Promise<CloseResult> {
    this.maybeFail('closePosition');
    const position = this.positions.get(input.positionId);
    if (position === undefined || position.status !== 'OPEN') {
      return 'NOT_OPEN';
    }
    this.positions.set(input.positionId, { ...position, status: 'CLOSED', pnl: input.realizedPnlInr });
    this.wallet = toPaise((this.wallet ?? 0) + input.creditInr);
    this.orders.push(input.order);
    return 'CLOSED';
  }
}

function entry(overrides: Partial<EntryOrder> = {}): EntryOrder {
  return {
    side: 'BUY',
    correlationId: 'ENT-1',
    underlying: 'NIFTY',
    contract: OPTION,
    quantity: 75,
    entryReference: 100,
    stopLossPrice: 70,
    targetPrice: 160,
    ...overrides,
  };
}

function exit(overrides: Partial<ExitOrder> = {}): ExitOrder {
  return {
    side: 'SELL',
    correlationId: 'EXT-1',
    underlying: 'NIFTY',
    positionId: 'ENT-1',
    contract: OPTION,
    quantity: 75,
    reason: 'MANUAL',
    referencePrice: 120,
    ...overrides,
  };
}

async function venue(store: MemoryPaperStore, slippageBps = 0, capital = 300_000): Promise<PostgresPaperExecutionPort> {
  const port = new PostgresPaperExecutionPort(store, {
    clientId: CLIENT,
    slippageBps,
    initialCapitalInr: capital,
    logger: SILENT,
    now: () => NOW,
  });
  await port.open();
  return port;
}

function collect(port: PostgresPaperExecutionPort): ExecutionEvent[] {
  const events: ExecutionEvent[] = [];
  port.onEvent((event) => events.push(event));
  return events;
}

const chargesFor = (buyPrice: number, sellPrice: number) =>
  roundTripChargesInr({ quantity: 75, buyPrice, sellPrice, exchangeSegment: OPTION.exchangeSegment });

const flush = () => new Promise<void>((resolve) => setImmediate(resolve));

describe('PostgresPaperExecutionPort', () => {
  it('debits the wallet on entry, credits it on exit net of charges, and realises P&L as the cash difference', async () => {
    const store = new MemoryPaperStore();
    const port = await venue(store, 0);
    const events = collect(port);
    await port.submitEntry(entry());
    await flush();
    assert.equal(store.wallet, 300_000 - 100 * 75, 'the premium is debited at entry');
    assert.equal(port.openPositionCount(), 1);

    await port.submitExit(exit());
    await flush();
    const netPnl = (120 - 100) * 75 - chargesFor(100, 120);
    assert.equal(store.wallet, 300_000 + netPnl, 'the exit proceeds less charges are credited');
    assert.equal(port.openPositionCount(), 0);
    assert.equal(store.positions.get('ENT-1')?.pnl, netPnl);
    assert.deepEqual(events.map((e) => e.kind), ['ENTRY_FILLED', 'EXIT_FILLED']);
    assert.equal(store.orders.length, 2, 'the entry and the exit are both recorded as orders');
  });

  it('applies slippage in the adverse direction on both legs', async () => {
    const store = new MemoryPaperStore();
    const port = await venue(store, 100);
    const events = collect(port);
    await port.submitEntry(entry());
    await port.submitExit(exit());
    await flush();
    const filled = events.find((e) => e.kind === 'ENTRY_FILLED');
    const closed = events.find((e) => e.kind === 'EXIT_FILLED');
    assert.equal(filled?.kind === 'ENTRY_FILLED' && filled.averagePrice, 101, 'entry pays up, rounded to tick');
    assert.equal(closed?.kind === 'EXIT_FILLED' && closed.averagePrice, 118.8, 'the exit receives 1% less, rounded down to tick');
  });

  it('refuses an entry the wallet cannot pay for, and places no position', async () => {
    const store = new MemoryPaperStore();
    const port = await venue(store, 0, 1_000);
    const events = collect(port);
    await port.submitEntry(entry());
    await flush();
    assert.equal(events[0]?.kind, 'ENTRY_REJECTED');
    assert.equal(events[0]?.kind === 'ENTRY_REJECTED' && events[0].reason, 'insufficient paper cash');
    assert.equal(port.openPositionCount(), 0);
    assert.equal(store.wallet, 1_000, 'no cash moved');
  });

  it('refuses a second entry with an id the venue already holds', async () => {
    const store = new MemoryPaperStore();
    const port = await venue(store);
    const events = collect(port);
    await port.submitEntry(entry());
    await port.submitEntry(entry());
    await flush();
    assert.equal(events.filter((e) => e.kind === 'ENTRY_FILLED').length, 1);
    assert.ok(events.some((e) => e.kind === 'ENTRY_REJECTED'), 'the duplicate is rejected');
    assert.equal(store.wallet, 300_000 - 100 * 75, 'the duplicate debited nothing');
  });

  it('reports an entry as UNCONFIRMED and fills nothing when the write fails', async () => {
    const store = new MemoryPaperStore();
    const port = await venue(store);
    const events = collect(port);
    store.failNext = 'openPosition';
    await port.submitEntry(entry());
    await flush();
    assert.equal(events[0]?.kind, 'ENTRY_UNCONFIRMED', 'a failed write halts the agent, it is never a fill');
    assert.equal(port.openPositionCount(), 0);
  });

  it('keeps the position open when the exit write fails, and lets a retry close it', async () => {
    const store = new MemoryPaperStore();
    const port = await venue(store);
    const events = collect(port);
    await port.submitEntry(entry());
    store.failNext = 'closePosition';
    await port.submitExit(exit());
    await flush();
    assert.equal(events.at(-1)?.kind, 'EXIT_UNCONFIRMED');
    assert.equal(port.openPositionCount(), 1, 'the venue still holds the position');
    assert.equal(store.positions.get('ENT-1')?.status, 'OPEN', 'and so does the database');

    await port.submitExit(exit({ correlationId: 'EXT-2' }));
    await flush();
    assert.equal(events.at(-1)?.kind, 'EXIT_FILLED');
    assert.equal(port.openPositionCount(), 0);
  });

  it('rejects an exit for an unknown position, and a partial exit it cannot model', async () => {
    const store = new MemoryPaperStore();
    const port = await venue(store);
    const events = collect(port);
    await port.submitExit(exit({ positionId: 'missing' }));
    await port.submitEntry(entry());
    await port.submitExit(exit({ quantity: 25 }));
    await flush();
    assert.equal(events[0]?.kind, 'EXIT_REJECTED');
    assert.equal(events.at(-1)?.kind, 'EXIT_REJECTED');
    const last = events.at(-1);
    assert.ok(last?.kind === 'EXIT_REJECTED' && last.reason.startsWith('partial'), 'the partial exit is named as unmodelled');
    assert.equal(port.openPositionCount(), 1);
  });

  it('closes a position once when an agent exit and a stop arrive together', async () => {
    const store = new MemoryPaperStore();
    const port = await venue(store);
    const events = collect(port);
    await port.submitEntry(entry());
    await flush();
    port.onOptionTick({ exchangeSegment: 'NSE_FNO', securityId: '48001', ltp: 60, ltt: NOW });
    await port.submitExit(exit());
    await flush();
    const closes = events.filter((e) => e.kind === 'EXIT_FILLED' || e.kind === 'PROTECTIVE_EXIT_FILLED');
    assert.equal(closes.length, 1, 'exactly one close reaches the agent');
    assert.equal(store.orders.filter((o) => o.kind !== 'ENTRY').length, 1, 'and exactly one exit order is recorded');
  });

  it('closes at the stop when the market gaps through it, and at the target otherwise', async () => {
    const store = new MemoryPaperStore();
    const port = await venue(store);
    const events = collect(port);
    await port.submitEntry(entry());
    await flush();
    port.onOptionTick({ exchangeSegment: 'NSE_FNO', securityId: '48001', ltp: 60, ltt: NOW });
    await flush();
    const stop = events.find((e) => e.kind === 'PROTECTIVE_EXIT_FILLED');
    assert.equal(stop?.kind === 'PROTECTIVE_EXIT_FILLED' && stop.averagePrice, 60);
    assert.equal(store.positions.get('ENT-1')?.pnl, (60 - 100) * 75 - chargesFor(100, 60));

    await port.submitEntry(entry({ correlationId: 'ENT-2' }));
    await flush();
    port.onOptionTick({ exchangeSegment: 'NSE_FNO', securityId: '48001', ltp: 165, ltt: NOW });
    await flush();
    const target = events.filter((e) => e.kind === 'PROTECTIVE_EXIT_FILLED').at(-1);
    assert.equal(target?.kind === 'PROTECTIVE_EXIT_FILLED' && target.reason, 'TARGET');
  });

  it('reports a protective exit that cannot be written as a halt, not a fill', async () => {
    const store = new MemoryPaperStore();
    const port = await venue(store);
    const events = collect(port);
    await port.submitEntry(entry());
    await flush();
    store.failNext = 'closePosition';
    port.onOptionTick({ exchangeSegment: 'NSE_FNO', securityId: '48001', ltp: 60, ltt: NOW });
    await flush();
    assert.equal(events.at(-1)?.kind, 'BROKER_MISMATCH');
    assert.equal(events.some((e) => e.kind === 'PROTECTIVE_EXIT_FILLED'), false);
  });

  it('restores the wallet and the open positions from the store, as a restart does', async () => {
    const store = new MemoryPaperStore();
    const first = await venue(store);
    await first.submitEntry(entry());
    await flush();

    const restarted = await venue(store);
    assert.equal(restarted.openPositionCount(), 1, 'the open position survives the restart');
    assert.equal(await restarted.cash(), 300_000 - 100 * 75, 'and so does the cash');
  });

  it('should cash-settle a carried position at intrinsic value once its expiry session has closed', async () => {
    const store = new MemoryPaperStore();
    await (await venue(store)).submitEntry(entry());
    await flush();
    let clock = istEpoch('2026-10-15', '15:29');
    const restart = async () => {
      const port = new PostgresPaperExecutionPort(store, { clientId: CLIENT, slippageBps: 0, initialCapitalInr: 300_000, logger: SILENT, now: () => clock });
      await port.open();
      return port;
    };
    const closes: string[] = [];
    const nifty = async (underlying: string, expiry: string) => {
      closes.push(`${underlying} ${expiry}`);
      return 22_500;
    };

    assert.deepEqual(await (await restart()).settleExpired(nifty), [], 'the expiry session is still trading');

    clock = istEpoch('2026-10-16', '09:00');
    const port = await restart();
    const settled = await port.settleExpired(nifty);
    assert.deepEqual(settled, [{ positionId: 'ENT-1', underlying: 'NIFTY', expiry: '2026-10-15', settlementPrice: 50 }]);
    assert.deepEqual(closes, ['NIFTY 2026-10-15'], 'settled against the expiry-day close');
    assert.equal(port.openPositionCount(), 0);
    assert.equal(store.positions.get('ENT-1')?.pnl, (50 - 100) * 75 - chargesFor(100, 50));
    assert.equal(store.orders.at(-1)?.kind, 'EXPIRY');
  });

  it('should settle an out-of-the-money expired option at zero', async () => {
    const store = new MemoryPaperStore();
    await (await venue(store)).submitEntry(entry());
    await flush();
    const port = new PostgresPaperExecutionPort(store, { clientId: CLIENT, slippageBps: 0, initialCapitalInr: 300_000, logger: SILENT, now: () => istEpoch('2026-10-19', '09:00') });
    await port.open();
    const settled = await port.settleExpired(async () => 22_000);
    assert.equal(settled[0]?.settlementPrice, 0);
    assert.equal(store.wallet, toPaise(300_000 - 100 * 75 - chargesFor(100, 0)), 'the premium is lost, and the charges with it');
  });

  it('refuses to trade before open(), so no order can see an unloaded wallet', async () => {
    const port = new PostgresPaperExecutionPort(new MemoryPaperStore(), {
      clientId: CLIENT,
      slippageBps: 0,
      initialCapitalInr: 300_000,
      logger: SILENT,
      now: () => NOW,
    });
    await assert.rejects(port.submitEntry(entry()), /before open\(\)/);
  });
});
