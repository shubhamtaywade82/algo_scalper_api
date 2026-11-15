import { strict as assert } from 'node:assert';
import { describe, it } from 'node:test';
import { GatewayExecutionPort } from '../src/execution/gatewayPort.js';
import type { GatewayOrder, GatewayOutcome, OrderGateway } from '../src/execution/orderGateway.js';
import type { EntryOrder, ExecutionEvent, ExitOrder } from '../src/execution/ports.js';
import { createConsoleLogger } from '../src/ops/logger.js';
import { contract, istEpoch } from './support/fixtures.js';

const NOW = istEpoch('2026-10-12', '10:00');
const SILENT = createConsoleLogger(() => undefined, () => NOW);
const OPTION = contract({ optionType: 'CE', strike: 22_450, securityId: '48001' });

/** A gateway that answers from a queue, and records every order it was asked to place. */
class ScriptedGateway implements OrderGateway {
  readonly sent: GatewayOrder[] = [];
  private readonly answers: Array<GatewayOutcome | Error> = [];
  positions = 0;

  answer(...outcomes: Array<GatewayOutcome | Error>): this {
    this.answers.push(...outcomes);
    return this;
  }

  async place(order: GatewayOrder): Promise<GatewayOutcome> {
    this.sent.push(order);
    const next = this.answers.shift();
    if (next === undefined) {
      throw new Error('no scripted answer left');
    }
    if (next instanceof Error) {
      throw next;
    }
    return next;
  }

  async openPositionCount(): Promise<number> {
    return this.positions;
  }
}

const FILLED = (quantity = 75, averagePrice = 100): GatewayOutcome => ({ kind: 'FILLED', filledQuantity: quantity, averagePrice });

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

function port(gateway: OrderGateway, mode: 'sandbox' | 'paper' = 'sandbox'): { port: GatewayExecutionPort; events: ExecutionEvent[] } {
  const events: ExecutionEvent[] = [];
  const created = new GatewayExecutionPort(gateway, { mode, logger: SILENT, now: () => NOW });
  created.onEvent((event) => events.push(event));
  return { port: created, events };
}

const flush = () => new Promise<void>((resolve) => setImmediate(resolve));
const tick = (ltp: number) => ({ exchangeSegment: 'NSE_FNO', securityId: '48001', ltp, ltt: NOW });

describe('GatewayExecutionPort', () => {
  it('reports an entry as filled only with the venue fill, and sends a market BUY', async () => {
    const gateway = new ScriptedGateway().answer(FILLED(75, 101));
    const { port: execution, events } = port(gateway);
    await execution.submitEntry(entry());
    await flush();
    assert.equal(events[0]?.kind, 'ENTRY_FILLED');
    assert.equal(events[0]?.kind === 'ENTRY_FILLED' && events[0].averagePrice, 101);
    assert.equal(gateway.sent[0]?.side, 'BUY');
    assert.equal(gateway.sent[0]?.reason, undefined);
  });

  it('maps a rejected entry to ENTRY_REJECTED and an unconfirmed one to ENTRY_UNCONFIRMED', async () => {
    const gateway = new ScriptedGateway().answer({ kind: 'REJECTED', reason: 'insufficient margin' }, { kind: 'UNCONFIRMED', reason: 'timeout' });
    const { port: execution, events } = port(gateway);
    await execution.submitEntry(entry());
    await execution.submitEntry(entry({ correlationId: 'ENT-2' }));
    await flush();
    assert.deepEqual(events.map((e) => e.kind), ['ENTRY_REJECTED', 'ENTRY_UNCONFIRMED']);
  });

  it('treats a gateway that throws as unconfirmed, so the agent halts instead of retrying', async () => {
    const { port: execution, events } = port(new ScriptedGateway().answer(new Error('socket reset')));
    await execution.submitEntry(entry());
    await flush();
    assert.equal(events[0]?.kind, 'ENTRY_UNCONFIRMED');
  });

  it('sends the stop-loss sell itself when the option LTP reaches the stop, and fills at the stop or better', async () => {
    const gateway = new ScriptedGateway().answer(FILLED(75, 100), FILLED(75, 60));
    const { port: execution, events } = port(gateway);
    await execution.submitEntry(entry());
    await flush();
    execution.onOptionTick(tick(60));
    await flush();
    const sell = gateway.sent.at(-1);
    assert.equal(sell?.side, 'SELL');
    assert.equal(sell?.reason, 'STOP_LOSS');
    assert.equal(sell?.referencePrice, 60, 'a gap through the stop prices at the LTP, not at the stop');
    const protective = events.find((e) => e.kind === 'PROTECTIVE_EXIT_FILLED');
    assert.equal(protective?.kind === 'PROTECTIVE_EXIT_FILLED' && protective.reason, 'STOP_LOSS');
  });

  it('closes at the target once, and never sends a second sell for a position already exiting', async () => {
    const gateway = new ScriptedGateway().answer(FILLED(75, 100), FILLED(75, 160));
    const { port: execution, events } = port(gateway);
    await execution.submitEntry(entry());
    await flush();
    execution.onOptionTick(tick(165));
    execution.onOptionTick(tick(170));
    await flush();
    assert.equal(gateway.sent.filter((o) => o.side === 'SELL').length, 1);
    assert.equal(events.filter((e) => e.kind === 'PROTECTIVE_EXIT_FILLED').length, 1);
  });

  it('halts with a broker mismatch when a protective sell does not settle, and keeps the position', async () => {
    const gateway = new ScriptedGateway().answer(FILLED(75, 100), { kind: 'REJECTED', reason: 'venue closed' });
    const { port: execution, events } = port(gateway);
    await execution.submitEntry(entry());
    await flush();
    execution.onOptionTick(tick(60));
    await flush();
    assert.equal(events.at(-1)?.kind, 'BROKER_MISMATCH');
    assert.equal(events.some((e) => e.kind === 'PROTECTIVE_EXIT_FILLED'), false);
  });

  it('fills an agent exit and forgets the position', async () => {
    const gateway = new ScriptedGateway().answer(FILLED(75, 100), FILLED(75, 118));
    const { port: execution, events } = port(gateway);
    await execution.submitEntry(entry());
    await execution.submitExit(exit());
    await flush();
    assert.equal(events.at(-1)?.kind, 'EXIT_FILLED');
    assert.equal(gateway.sent.at(-1)?.reason, 'MANUAL');
    execution.onOptionTick(tick(60));
    await flush();
    assert.equal(gateway.sent.length, 2, 'no stop fires for a closed position');
  });

  it('keeps an unconfirmed exit marked in flight, so a later tick cannot sell the same position again', async () => {
    const gateway = new ScriptedGateway().answer(FILLED(75, 100), { kind: 'UNCONFIRMED', reason: 'timeout' });
    const { port: execution, events } = port(gateway);
    await execution.submitEntry(entry());
    await execution.submitExit(exit());
    await flush();
    assert.equal(events.at(-1)?.kind, 'EXIT_UNCONFIRMED');
    execution.onOptionTick(tick(60));
    await flush();
    assert.equal(gateway.sent.length, 2, 'a sell that may have filled is not sent again');
  });

  it('reports a rejected agent exit and clears the in-flight mark, so the exit can be retried', async () => {
    const gateway = new ScriptedGateway().answer(FILLED(75, 100), { kind: 'REJECTED', reason: 'market closed' }, FILLED(75, 119));
    const { port: execution, events } = port(gateway);
    await execution.submitEntry(entry());
    await execution.submitExit(exit());
    await execution.submitExit(exit({ correlationId: 'EXT-2' }));
    await flush();
    assert.deepEqual(events.slice(1).map((e) => e.kind), ['EXIT_REJECTED', 'EXIT_FILLED']);
  });

  it('refuses an exit for an unknown position, and a partial exit it cannot send', async () => {
    const gateway = new ScriptedGateway().answer(FILLED(75, 100));
    const { port: execution, events } = port(gateway);
    await execution.submitExit(exit({ positionId: 'nope' }));
    await execution.submitEntry(entry());
    await execution.submitExit(exit({ quantity: 25 }));
    await flush();
    assert.equal(events[0]?.kind, 'EXIT_REJECTED');
    assert.equal(events.at(-1)?.kind, 'EXIT_REJECTED');
    assert.equal(gateway.sent.length, 1, 'only the entry reached the venue');
  });

  it('reports the venue open-position count for the start check', async () => {
    const gateway = new ScriptedGateway();
    gateway.positions = 2;
    const { port: execution } = port(gateway);
    assert.equal(await execution.openPositionCount(), 2);
  });
});

describe('GatewayExecutionPort protection, trailing stop and gap-through', () => {
  it('reports client-side protection', () => {
    const { port: created } = port(new ScriptedGateway());
    assert.equal(created.protection, 'CLIENT_SIDE');
  });

  it('trails the stop up with the high-water mark, never lowers it, and sells once it is reached', async () => {
    const gateway = new ScriptedGateway().answer(FILLED(75, 100), FILLED(75, 118));
    const { port: created } = port(gateway);
    await created.submitEntry(entry({ trailingJump: 5, breakevenAtRr: 1 }));
    await flush();
    for (const ltp of [120, 140, 150, 135]) {
      created.onOptionTick(tick(ltp));
      await flush();
    }
    assert.equal(gateway.sent.length, 1, 'no sell while the price stays above the trailed stop');
    created.onOptionTick(tick(119));
    await flush();
    assert.equal(gateway.sent.length, 2);
    assert.equal(gateway.sent[1]?.side, 'SELL');
    assert.equal(gateway.sent[1]?.reason, 'STOP_LOSS');
  });

  it('sells once on a gap through the stop, even while more ticks arrive below it', async () => {
    const gateway = new ScriptedGateway().answer(FILLED(75, 100), FILLED(75, 60));
    const { port: created } = port(gateway);
    await created.submitEntry(entry());
    await flush();
    created.onOptionTick(tick(60));
    created.onOptionTick(tick(55));
    await flush();
    assert.equal(gateway.sent.length, 2, 'one protective sell, not one per tick');
    assert.equal(gateway.sent[1]?.reason, 'STOP_LOSS');
  });
});
