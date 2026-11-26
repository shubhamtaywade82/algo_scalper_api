import { strict as assert } from 'node:assert';
import { describe, it } from 'node:test';
import { PaperExecutionPort } from '../src/execution/paper.js';
import type { EntryOrder, ExecutionEvent, ExitOrder } from '../src/execution/ports.js';
import { contract, istEpoch } from './support/fixtures.js';

const TICK_TIME = istEpoch('2026-10-12', '10:00');
const OPTION = contract({ optionType: 'CE', strike: 22_450, securityId: '48001' });

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

function collect(port: PaperExecutionPort): ExecutionEvent[] {
  const events: ExecutionEvent[] = [];
  port.onEvent((event) => events.push(event));
  return events;
}

const flush = () => new Promise<void>((resolve) => setImmediate(resolve));

describe('PaperExecutionPort', () => {
  it('fills an entry at the reference premium plus slippage, rounded up to tick', async () => {
    const port = new PaperExecutionPort({ slippageBps: 100, now: () => TICK_TIME });
    const events = collect(port);
    await port.submitEntry(entry());
    await flush();
    assert.deepEqual(events[0], {
      kind: 'ENTRY_FILLED',
      correlationId: 'ENT-1',
      underlying: 'NIFTY',
      quantity: 75,
      averagePrice: 101,
      at: TICK_TIME,
    });
  });

  it('fills the stop at the LTP when the market gaps through it, never at the stop', async () => {
    const port = new PaperExecutionPort({ slippageBps: 0 });
    const events = collect(port);
    await port.submitEntry(entry());
    port.onOptionTick({ exchangeSegment: 'NSE_FNO', securityId: '48001', ltp: 60, ltt: TICK_TIME });
    await flush();
    const protective = events.find((event) => event.kind === 'PROTECTIVE_EXIT_FILLED');
    assert.equal(protective?.kind === 'PROTECTIVE_EXIT_FILLED' && protective.averagePrice, 60);
    assert.equal(protective?.kind === 'PROTECTIVE_EXIT_FILLED' && protective.reason, 'STOP_LOSS');
  });

  it('fills the target at the target price and only once', async () => {
    const port = new PaperExecutionPort({ slippageBps: 0 });
    const events = collect(port);
    await port.submitEntry(entry());
    port.onOptionTick({ exchangeSegment: 'NSE_FNO', securityId: '48001', ltp: 170, ltt: TICK_TIME });
    port.onOptionTick({ exchangeSegment: 'NSE_FNO', securityId: '48001', ltp: 175, ltt: TICK_TIME });
    await flush();
    const exits = events.filter((event) => event.kind === 'PROTECTIVE_EXIT_FILLED');
    assert.equal(exits.length, 1);
    assert.equal(exits[0]?.kind === 'PROTECTIVE_EXIT_FILLED' && exits[0].averagePrice, 160);
  });

  it('ignores ticks for other instruments and other segments', async () => {
    const port = new PaperExecutionPort({ slippageBps: 0 });
    const events = collect(port);
    await port.submitEntry(entry());
    port.onOptionTick({ exchangeSegment: 'BSE_FNO', securityId: '48001', ltp: 10, ltt: TICK_TIME });
    port.onOptionTick({ exchangeSegment: 'NSE_FNO', securityId: '99999', ltp: 10, ltt: TICK_TIME });
    await flush();
    assert.equal(events.filter((event) => event.kind === 'PROTECTIVE_EXIT_FILLED').length, 0);
  });

  it('closes an open position on an agent exit and rejects an exit for an unknown position', async () => {
    const port = new PaperExecutionPort({ slippageBps: 0 });
    const events = collect(port);
    await port.submitEntry(entry());
    const exit: ExitOrder = {
      side: 'SELL',
      correlationId: 'EXT-1',
      underlying: 'NIFTY',
      positionId: 'ENT-1',
      contract: OPTION,
      quantity: 75,
      reason: 'TIME_STOP',
      referencePrice: 112.3,
    };
    await port.submitExit(exit);
    await port.submitExit({ ...exit, correlationId: 'EXT-2', positionId: 'missing' });
    await flush();
    assert.equal(events.at(-2)?.kind, 'EXIT_FILLED');
    assert.equal(events.at(-1)?.kind, 'EXIT_REJECTED');
  });
});
