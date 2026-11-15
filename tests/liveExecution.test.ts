import { strict as assert } from 'node:assert';
import { describe, it } from 'node:test';
import { ApiResponseError } from '@nemesis-oss/dhanhq-sdk';
import { classifyPlacementError, LiveExecutionPort, type LiveClient } from '../src/dhan/liveExecution.js';
import type { EntryOrder, ExecutionEvent, ExitOrder } from '../src/execution/ports.js';
import { contract } from './support/fixtures.js';

const SILENT = { info() {}, warn() {}, error() {} };
const OPTION = contract({ optionType: 'CE', strike: 22_450, securityId: '48001' });
const SEG = 'NSE_FNO';

interface FakeOptions {
  placeError?: unknown;
  sellError?: unknown;
  cancelError?: unknown;
  positions?: Array<Record<string, unknown>>;
  positionsError?: unknown;
  /** Replaces the default super order book, in which a leg reads CANCELLED once its cancel was accepted. */
  superOrderBook?: () => unknown[];
  killSwitchReadBack?: string;
  /** The order id a SELL placement returns. Without one the adapter cannot cancel a resting SELL. */
  sellOrderId?: string;
  /** Fails every cancel of a plain order while set. */
  orderCancelError?: unknown;
  /** Fails the broker P&L exit calls in order, one failure per call. Calls past the end succeed. */
  pnlExitFailures?: unknown[];
  /** What the order book returns for a correlation id. Without it the read fails. */
  orderByCorrelationId?: (correlationId: string) => Record<string, unknown>;
}

function fakeBroker(options: FakeOptions = {}) {
  const orderHandlers: Array<(state: unknown) => void> = [];
  const calls = {
    superPlace: [] as Array<Record<string, unknown>>,
    superCancel: [] as Array<Record<string, unknown>>,
    place: [] as Array<Record<string, unknown>>,
    kill: [] as string[],
    cancel: [] as string[],
    pnlExit: [] as Array<Record<string, unknown>>,
    orderReads: [] as string[],
    superList: 0,
  };
  const cancelledLegs = new Set<unknown>();
  const defaultBook = () => [
    {
      orderId: 'SUPER-1',
      orderStatus: 'TRADED',
      legDetails: ['STOP_LOSS_LEG', 'TARGET_LEG'].map((legName) => ({
        legName,
        orderStatus: cancelledLegs.has(legName) ? 'CANCELLED' : 'PENDING',
      })),
    },
  ];
  const client = {
    ws: {
      orders: {
        on: (event: string, handler: (state: unknown) => void) => {
          if (event === 'order') {
            orderHandlers.push(handler);
          }
        },
      },
    },
    superOrders: {
      place: async (request: Record<string, unknown>) => {
        calls.superPlace.push(request);
        if (options.placeError !== undefined) {
          throw options.placeError;
        }
        return { correlationId: request['correlationId'], data: { orderId: 'SUPER-1' } };
      },
      cancel: async (request: Record<string, unknown>) => {
        calls.superCancel.push(request);
        if (options.cancelError !== undefined) {
          throw options.cancelError;
        }
        cancelledLegs.add(request['orderLeg']);
        return {};
      },
      list: async () => {
        calls.superList += 1;
        return (options.superOrderBook ?? defaultBook)();
      },
    },
    orders: {
      place: async (request: Record<string, unknown>) => {
        calls.place.push(request);
        if (options.sellError !== undefined) {
          throw options.sellError;
        }
        return { correlationId: request['correlationId'], data: options.sellOrderId === undefined ? {} : { orderId: options.sellOrderId } };
      },
      cancel: async (orderId: string) => {
        calls.cancel.push(orderId);
        if (options.orderCancelError !== undefined) {
          throw options.orderCancelError;
        }
        return {};
      },
      getByCorrelationId: async (correlationId: string) => {
        calls.orderReads.push(correlationId);
        if (options.orderByCorrelationId === undefined) {
          throw new Error('order book unavailable');
        }
        return options.orderByCorrelationId(correlationId);
      },
    },
    positions: {
      list: async () => {
        if (options.positionsError !== undefined) {
          throw options.positionsError;
        }
        return options.positions ?? [];
      },
    },
    traderControls: {
      setPnlExit: async (request: Record<string, unknown>) => {
        calls.pnlExit.push(request);
        const failure = options.pnlExitFailures?.shift();
        if (failure !== undefined) {
          throw failure;
        }
        return { message: 'ACTIVE' };
      },
      setKillSwitch: async (status: string) => {
        calls.kill.push(status);
        return {};
      },
      getKillSwitchStatus: async () => ({ killSwitchStatus: options.killSwitchReadBack ?? calls.kill.at(-1) }),
    },
  };
  const emitOrder = (state: Record<string, unknown>) => {
    for (const handler of orderHandlers) {
      handler(state);
    }
  };
  return { client: client as unknown as LiveClient, calls, emitOrder };
}

function entry(correlationId = 'ENT-1', quantity = 75): EntryOrder {
  return {
    side: 'BUY',
    correlationId,
    underlying: 'NIFTY',
    contract: OPTION,
    quantity,
    entryReference: 101,
    stopLossPrice: 70.05,
    targetPrice: 162.05,
  };
}

function exit(quantity = 75): ExitOrder {
  return {
    side: 'SELL',
    correlationId: 'EXT-1',
    underlying: 'NIFTY',
    positionId: 'ENT-1',
    contract: OPTION,
    quantity,
    reason: 'TIME_STOP',
    referencePrice: 112,
  };
}

const settle = () => new Promise<void>((resolve) => setTimeout(resolve, 15));

function port(broker: ReturnType<typeof fakeBroker>, orderTimeoutMs = 200, reconcileIntervalMs = 60_000) {
  const live = new LiveExecutionPort(broker.client, { mode: 'live', orderTimeoutMs, reconcileIntervalMs, logger: SILENT });
  const events: ExecutionEvent[] = [];
  live.onEvent((event) => events.push(event));
  return { live, events };
}

function brokerRow(netQty: number, extra: Record<string, unknown> = {}) {
  return { securityId: '48001', exchangeSegment: SEG, productType: 'INTRADAY', netQty, ...extra };
}

function dayTotals(dayBuyQty: number, dayBuyValue: number, daySellQty: number, daySellValue: number) {
  return { dayBuyQty, dayBuyValue, daySellQty, daySellValue };
}

function setPositions(broker: ReturnType<typeof fakeBroker>, rows: Array<Record<string, unknown>>): void {
  (broker.client as unknown as { positions: { list: () => Promise<unknown[]> } }).positions.list = async () => rows;
}

describe('classifyPlacementError', () => {
  it('treats definitive client rejections as REJECTED', () => {
    assert.equal(classifyPlacementError(new ApiResponseError('bad quantity', 400)), 'REJECTED');
    assert.equal(classifyPlacementError(new ApiResponseError('forbidden', 403)), 'REJECTED');
  });

  it('treats anything that may have reached the venue as UNCONFIRMED', () => {
    assert.equal(classifyPlacementError(new ApiResponseError('server error', 500)), 'UNCONFIRMED');
    assert.equal(classifyPlacementError(new ApiResponseError('token expired', 401)), 'UNCONFIRMED');
    assert.equal(classifyPlacementError(new ApiResponseError('too many requests', 429)), 'UNCONFIRMED');
    assert.equal(classifyPlacementError(new Error('socket hang up')), 'UNCONFIRMED');
  });
});

describe('LiveExecutionPort broker id limit', () => {
  it('refuses an entry whose correlation id is over 30 characters, and never sends it', async () => {
    const broker = fakeBroker();
    const { live, events } = port(broker);
    await live.submitEntry(entry('ENT-LONG-ID-THAT-THE-BROKER-WOULD-REFUSE'));
    await settle();
    assert.equal(events[0]?.kind, 'ENTRY_REJECTED');
    assert.equal(broker.calls.superPlace.length, 0, 'the oversize id never reached Dhan');
  });

  it('refuses an exit whose correlation id is over 30 characters, and never sends the sell', async () => {
    const broker = fakeBroker({ positions: [brokerRow(75)] });
    const { live, events } = port(broker);
    await live.submitEntry(entry());
    await settle();
    await live.submitExit({ ...exit(), correlationId: 'EXT-ENT-NIFTY-LONG-ID-THAT-OVERRUNS-THE-LIMIT' });
    await settle();
    assert.equal(events.at(-1)?.kind, 'EXIT_REJECTED');
    assert.equal(broker.calls.place.length, 0, 'no sell went to Dhan');
  });
});

describe('LiveExecutionPort entries', () => {
  it('confirms a fill only from the order-update stream and reports its average price', async () => {
    const broker = fakeBroker();
    const { live, events } = port(broker);
    await live.submitEntry(entry());
    assert.equal(events.length, 0, 'HTTP acceptance alone is not a fill');
    broker.emitOrder({ orderId: 'SUPER-1', correlationId: 'ENT-1', status: 'TRADED', tradedQty: 75, averageTradedPrice: 101.5, securityId: '48001', raw: {} });
    await settle();
    assert.deepEqual(events, [
      { kind: 'ENTRY_FILLED', correlationId: 'ENT-1', underlying: 'NIFTY', quantity: 75, averagePrice: 101.5, at: events[0] && (events[0] as { at: number }).at },
    ]);
    assert.equal(broker.calls.superPlace[0]?.['stopLossPrice'], 70.05, 'stop and target travel with the entry');
    assert.equal(broker.calls.superPlace[0]?.['productType'], 'INTRADAY');
    assert.equal(broker.calls.superPlace[0]?.['transactionType'], 'BUY');
    await live.close();
  });

  it('reports a definitive placement rejection as ENTRY_REJECTED without tracking a position', async () => {
    const { live, events } = port(fakeBroker({ placeError: new ApiResponseError('margin short', 400) }));
    await live.submitEntry(entry());
    assert.equal(events[0]?.kind, 'ENTRY_REJECTED');
    await live.close();
  });

  it('reports an ambiguous placement failure as ENTRY_UNCONFIRMED so trading halts', async () => {
    const { live, events } = port(fakeBroker({ placeError: new ApiResponseError('gateway timeout', 504) }));
    await live.submitEntry(entry());
    assert.equal(events[0]?.kind, 'ENTRY_UNCONFIRMED');
    await live.close();
  });

  it('should send the entry as a LIMIT at the entry reference so a fill cannot exceed the sized risk', async () => {
    const broker = fakeBroker();
    const { live } = port(broker);
    await live.submitEntry(entry());
    assert.equal(broker.calls.superPlace[0]?.['orderType'], 'LIMIT');
    assert.equal(broker.calls.superPlace[0]?.['price'], 101);
    await live.close();
  });

  it('reports ENTRY_UNCONFIRMED when the entry neither settles nor confirms its cancel', async () => {
    const broker = fakeBroker();
    const { live, events } = port(broker, 30);
    await live.submitEntry(entry());
    await new Promise<void>((resolve) => setTimeout(resolve, 100));
    assert.deepEqual(broker.calls.superCancel, [{ orderId: 'SUPER-1', orderLeg: 'ENTRY_LEG' }]);
    assert.equal(events.at(-1)?.kind, 'ENTRY_UNCONFIRMED');
    await live.close();
  });

  it('should cancel an unfilled limit entry at the timeout and report it rejected', async () => {
    const broker = fakeBroker();
    const { live, events } = port(broker, 30);
    await live.submitEntry(entry());
    await new Promise<void>((resolve) => setTimeout(resolve, 40));
    assert.deepEqual(broker.calls.superCancel, [{ orderId: 'SUPER-1', orderLeg: 'ENTRY_LEG' }]);
    broker.emitOrder({ orderId: 'SUPER-1', correlationId: 'ENT-1', status: 'CANCELLED', tradedQty: 0, securityId: '48001', raw: {} });
    await settle();
    assert.equal(events.at(-1)?.kind, 'ENTRY_REJECTED');
    await live.close();
  });

  it('should report the filled part of a limit entry cancelled at the timeout', async () => {
    const broker = fakeBroker();
    const { live, events } = port(broker, 30);
    await live.submitEntry(entry());
    await new Promise<void>((resolve) => setTimeout(resolve, 40));
    broker.emitOrder({ orderId: 'SUPER-1', correlationId: 'ENT-1', status: 'CANCELLED', tradedQty: 25, averageTradedPrice: 100.5, securityId: '48001', raw: {} });
    await settle();
    const filled = events.at(-1);
    assert.equal(filled?.kind, 'ENTRY_FILLED');
    assert.equal((filled as { quantity: number }).quantity, 25);
    await live.close();
  });

  it('reports ENTRY_UNCONFIRMED when the cancel of an unfilled entry fails', async () => {
    const broker = fakeBroker({ cancelError: new ApiResponseError('gateway timeout', 504) });
    const { live, events } = port(broker, 30);
    await live.submitEntry(entry());
    await new Promise<void>((resolve) => setTimeout(resolve, 60));
    assert.equal(events.at(-1)?.kind, 'ENTRY_UNCONFIRMED');
    await live.close();
  });

  it('reports a rejected order with no fill as ENTRY_REJECTED', async () => {
    const broker = fakeBroker();
    const { live, events } = port(broker);
    await live.submitEntry(entry());
    broker.emitOrder({ orderId: 'SUPER-1', correlationId: 'ENT-1', status: 'REJECTED', tradedQty: 0, securityId: '48001', raw: {} });
    await settle();
    assert.equal(events[0]?.kind, 'ENTRY_REJECTED');
    await live.close();
  });
});

describe('LiveExecutionPort exits', () => {
  it('sends a SELL capped at the broker net long quantity after detaching the bracket legs', async () => {
    const broker = fakeBroker({ positions: [brokerRow(75)] });
    const { live, events } = port(broker);
    await live.submitEntry(entry());
    broker.emitOrder({ orderId: 'SUPER-1', correlationId: 'ENT-1', status: 'TRADED', tradedQty: 75, averageTradedPrice: 101, securityId: '48001', raw: {} });
    await settle();
    await live.submitExit(exit(150));
    assert.deepEqual(broker.calls.superCancel.map((call) => call['orderLeg']), ['STOP_LOSS_LEG', 'TARGET_LEG']);
    assert.equal(broker.calls.place.length, 1);
    assert.equal(broker.calls.place[0]?.['transactionType'], 'SELL');
    assert.equal(broker.calls.place[0]?.['quantity'], 75, 'never sell more than the broker reports as held');
    broker.emitOrder({ orderId: 'EXIT-1', correlationId: 'EXT-1', status: 'TRADED', tradedQty: 75, averageTradedPrice: 112, securityId: '48001', raw: {} });
    await settle();
    assert.equal(events.at(-1)?.kind, 'EXIT_FILLED');
    await live.close();
  });

  it('never sends a SELL when the broker reports no long quantity, and records the external close instead', async () => {
    const broker = fakeBroker();
    const { live, events } = port(broker);
    await live.submitEntry(entry());
    broker.emitOrder({ orderId: 'SUPER-1', correlationId: 'ENT-1', status: 'TRADED', tradedQty: 75, averageTradedPrice: 101, securityId: '48001', raw: {} });
    await settle();
    setPositions(broker, [brokerRow(0, dayTotals(75, 7575, 75, 5257.5))]);
    await live.submitExit(exit());
    assert.equal(broker.calls.place.length, 0, 'a SELL here would open a short option');
    assert.deepEqual(events.at(-1), {
      kind: 'PROTECTIVE_EXIT_FILLED',
      underlying: 'NIFTY',
      positionId: 'ENT-1',
      quantity: 75,
      averagePrice: 5257.5 / 75,
      reason: 'EXTERNAL',
      at: (events.at(-1) as { at: number }).at,
    });
    await live.close();
  });

  it('refuses to exit while a protective leg may still be active', async () => {
    const broker = fakeBroker({ positions: [brokerRow(75)], cancelError: new ApiResponseError('leg not cancellable', 400) });
    const { live, events } = port(broker);
    await live.submitEntry(entry());
    broker.emitOrder({ orderId: 'SUPER-1', correlationId: 'ENT-1', status: 'TRADED', tradedQty: 75, averageTradedPrice: 101, securityId: '48001', raw: {} });
    await settle();
    await live.submitExit(exit());
    assert.equal(broker.calls.place.length, 0);
    assert.equal(events.at(-1)?.kind, 'EXIT_UNCONFIRMED');
    await live.close();
  });

  it('waits for both legs to report CANCELLED before sending the SELL', async () => {
    let reads = 0;
    const book = (status: string) => [
      { orderId: 'SUPER-1', orderStatus: 'TRADED', legDetails: [{ legName: 'STOP_LOSS_LEG', orderStatus: status }, { legName: 'TARGET_LEG', orderStatus: status }] },
    ];
    const broker = fakeBroker({ positions: [brokerRow(75)], superOrderBook: () => book((reads += 1) < 3 ? 'PENDING' : 'CANCELLED') });
    const { live } = port(broker);
    await live.submitEntry(entry());
    broker.emitOrder({ orderId: 'SUPER-1', correlationId: 'ENT-1', status: 'TRADED', tradedQty: 75, averageTradedPrice: 101, securityId: '48001', raw: {} });
    await settle();
    await live.submitExit(exit());
    assert.equal(broker.calls.superList, 3, 'polled until the broker reported both legs cancelled');
    assert.equal(broker.calls.place.length, 1);
    await live.close();
  });

  it('records the protective exit and sends no SELL when the stop leg traded during the cancel', async () => {
    const broker = fakeBroker({
      positions: [brokerRow(75)],
      cancelError: new ApiResponseError('leg not cancellable', 400),
      superOrderBook: () => {
        setPositions(broker, [brokerRow(0, dayTotals(75, 7575, 75, 5250))]);
        return [
          { orderId: 'SUPER-1', orderStatus: 'TRADED', legDetails: [{ legName: 'STOP_LOSS_LEG', orderStatus: 'TRADED' }, { legName: 'TARGET_LEG', orderStatus: 'CANCELLED' }] },
        ];
      },
    });
    const { live, events } = port(broker);
    await live.submitEntry(entry());
    broker.emitOrder({ orderId: 'SUPER-1', correlationId: 'ENT-1', status: 'TRADED', tradedQty: 75, averageTradedPrice: 101, securityId: '48001', raw: {} });
    await settle();
    await live.submitExit(exit());
    assert.equal(broker.calls.place.length, 0, 'a SELL here would open a short option');
    assert.equal(events.at(-1)?.kind, 'PROTECTIVE_EXIT_FILLED');
    await live.close();
  });

  it('refuses to exit when an accepted cancel never reaches a terminal leg status', async () => {
    const pending = [
      { orderId: 'SUPER-1', orderStatus: 'TRADED', legDetails: [{ legName: 'STOP_LOSS_LEG', orderStatus: 'PENDING' }, { legName: 'TARGET_LEG', orderStatus: 'CANCELLED' }] },
    ];
    const broker = fakeBroker({ positions: [brokerRow(75)], superOrderBook: () => pending });
    const { live, events } = port(broker);
    await live.submitEntry(entry());
    broker.emitOrder({ orderId: 'SUPER-1', correlationId: 'ENT-1', status: 'TRADED', tradedQty: 75, averageTradedPrice: 101, securityId: '48001', raw: {} });
    await settle();
    await live.submitExit(exit());
    assert.equal(broker.calls.place.length, 0);
    assert.equal(events.at(-1)?.kind, 'EXIT_UNCONFIRMED');
    await live.close();
  });

  it('refuses to exit when the super order is missing from the order book', async () => {
    const broker = fakeBroker({ positions: [brokerRow(75)], superOrderBook: () => [] });
    const { live, events } = port(broker);
    await live.submitEntry(entry());
    broker.emitOrder({ orderId: 'SUPER-1', correlationId: 'ENT-1', status: 'TRADED', tradedQty: 75, averageTradedPrice: 101, securityId: '48001', raw: {} });
    await settle();
    await live.submitExit(exit());
    assert.equal(broker.calls.place.length, 0);
    assert.equal(events.at(-1)?.kind, 'EXIT_UNCONFIRMED');
    await live.close();
  });

  it('halts on a net short position rather than compounding the exposure', async () => {
    const broker = fakeBroker({ positions: [brokerRow(-75)] });
    const { live, events } = port(broker);
    await live.submitEntry(entry());
    broker.emitOrder({ orderId: 'SUPER-1', correlationId: 'ENT-1', status: 'TRADED', tradedQty: 75, averageTradedPrice: 101, securityId: '48001', raw: {} });
    await settle();
    await live.submitExit(exit());
    assert.equal(broker.calls.place.length, 0);
    assert.equal(events.at(-1)?.kind, 'BROKER_MISMATCH');
    await live.close();
  });

  it('does not send an exit when broker positions cannot be read', async () => {
    const broker = fakeBroker({ positions: [brokerRow(75)] });
    const { live, events } = port(broker);
    await live.submitEntry(entry());
    broker.emitOrder({ orderId: 'SUPER-1', correlationId: 'ENT-1', status: 'TRADED', tradedQty: 75, averageTradedPrice: 101, securityId: '48001', raw: {} });
    await settle();
    const failing = fakeBroker({ positionsError: new Error('read timeout') });
    const second = port(failing);
    await second.live.submitEntry(entry('ENT-2'));
    failing.emitOrder({ orderId: 'SUPER-1', correlationId: 'ENT-2', status: 'TRADED', tradedQty: 75, averageTradedPrice: 101, securityId: '48001', raw: {} });
    await settle();
    await second.live.submitExit({ ...exit(), positionId: 'ENT-2' });
    assert.equal(failing.calls.place.length, 0);
    assert.equal(second.events.at(-1)?.kind, 'EXIT_UNCONFIRMED');
    assert.equal(events.at(-1)?.kind, 'ENTRY_FILLED');
    await live.close();
    await second.live.close();
  });
});

describe('LiveExecutionPort ambiguous exits (failure injection)', () => {
  const FILLED_ENTRY = { orderId: 'SUPER-1', correlationId: 'ENT-1', status: 'TRADED', tradedQty: 75, averageTradedPrice: 101, securityId: '48001', raw: {} };

  it('never resends a SELL whose placement failed ambiguously, because the first may have reached the venue', async () => {
    const broker = fakeBroker({ positions: [brokerRow(75)], sellError: new Error('socket hang up') });
    const { live, events } = port(broker);
    await live.submitEntry(entry());
    broker.emitOrder(FILLED_ENTRY);
    await settle();
    await live.submitExit(exit());
    assert.equal(events.at(-1)?.kind, 'EXIT_UNCONFIRMED');
    await live.submitExit(exit());
    assert.equal(broker.calls.place.length, 1, 'a second SELL could leave the account net short');
    assert.equal(events.at(-1)?.kind, 'EXIT_UNCONFIRMED');
    await live.close();
  });

  it('never resends a SELL still unresolved when its outcome timed out, and sends nothing while the broker shows the position open', async () => {
    const broker = fakeBroker({ positions: [brokerRow(75)] });
    const { live, events } = port(broker, 50);
    await live.submitEntry(entry());
    broker.emitOrder(FILLED_ENTRY);
    await settle();
    await live.submitExit(exit());
    await new Promise((resolve) => setTimeout(resolve, 150));
    assert.equal(broker.calls.place.length, 1, 'the first SELL was accepted and is still outstanding');
    assert.equal(events.at(-1)?.kind, 'EXIT_UNCONFIRMED');
    await live.submitExit(exit());
    assert.equal(broker.calls.place.length, 1, 'the retry must not place a second SELL');
    await live.close();
  });

  it('still retries an exit after the broker definitively rejects the SELL', async () => {
    const broker = fakeBroker({ positions: [brokerRow(75)] });
    const { live, events } = port(broker);
    await live.submitEntry(entry());
    broker.emitOrder(FILLED_ENTRY);
    await settle();
    await live.submitExit(exit());
    broker.emitOrder({ orderId: 'EXIT-1', correlationId: 'EXT-1', status: 'REJECTED', tradedQty: 0, securityId: '48001', raw: {} });
    await settle();
    assert.equal(events.at(-1)?.kind, 'EXIT_REJECTED');
    await live.submitExit(exit());
    assert.equal(broker.calls.place.length, 2, 'a known rejection leaves nothing outstanding, so the exit may be sent again');
    await live.close();
  });
});

describe('LiveExecutionPort broker kill switch', () => {
  it('should resolve once the broker reads the switch back as activated', async () => {
    const broker = fakeBroker();
    const { live } = port(broker);
    await live.engageBrokerKillSwitch('test');
    assert.deepEqual(broker.calls.kill, ['ACTIVATE']);
    await live.close();
  });

  it('should reject when the broker reads the switch back as not activated', async () => {
    const broker = fakeBroker({ killSwitchReadBack: 'DEACTIVATE' });
    const { live } = port(broker);
    await assert.rejects(live.engageBrokerKillSwitch('test'), /DEACTIVATE/);
    await live.close();
  });
});

describe('LiveExecutionPort unconfirmed entries', () => {
  const ELEVEN_MINUTES = 11 * 60_000;

  function clockedPort(broker: ReturnType<typeof fakeBroker>, clock: { now: number }) {
    const live = new LiveExecutionPort(broker.client, { mode: 'live', orderTimeoutMs: 200, reconcileIntervalMs: 10, logger: SILENT, now: () => clock.now });
    const events: ExecutionEvent[] = [];
    live.onEvent((event) => events.push(event));
    return { live, events };
  }

  it('should keep tracking an unconfirmed entry the order book still shows live, and adopt its late fill', async () => {
    const clock = { now: 0 };
    const broker = fakeBroker({ placeError: new ApiResponseError('gateway timeout', 504), superOrderBook: () => [{ orderId: 'X', correlationId: 'ENT-1', orderStatus: 'PENDING' }] });
    const { live, events } = clockedPort(broker, clock);
    live.start();
    await live.submitEntry(entry());
    clock.now = ELEVEN_MINUTES;
    await settle();
    setPositions(broker, [brokerRow(75)]);
    await settle();
    assert.equal(events.at(-1)?.kind, 'ENTRY_FILLED', 'a fill after the retention window is still adopted');
    await live.close();
  });

  it('should drop an unconfirmed entry once the order book shows it never reached the broker', async () => {
    const clock = { now: 0 };
    const broker = fakeBroker({ placeError: new ApiResponseError('gateway timeout', 504), superOrderBook: () => [] });
    const { live, events } = clockedPort(broker, clock);
    live.start();
    await live.submitEntry(entry());
    clock.now = ELEVEN_MINUTES;
    await settle();
    await live.submitExit(exit());
    assert.equal(events.at(-1)?.kind, 'EXIT_REJECTED', 'no longer tracked');
    await live.close();
  });

  it('should keep an unconfirmed entry while the order book cannot be read', async () => {
    const clock = { now: 0 };
    const broker = fakeBroker({
      placeError: new ApiResponseError('gateway timeout', 504),
      superOrderBook: () => {
        throw new Error('read timeout');
      },
    });
    const { live, events } = clockedPort(broker, clock);
    live.start();
    await live.submitEntry(entry());
    clock.now = ELEVEN_MINUTES;
    await settle();
    setPositions(broker, [brokerRow(75)]);
    await settle();
    assert.equal(events.at(-1)?.kind, 'ENTRY_FILLED');
    await live.close();
  });
});

describe('LiveExecutionPort broker position rows', () => {
  /** Rows before the entry, while the position is open, and after the bracket closed it. */
  async function bracketCloseAfter(
    before: Array<Record<string, unknown>>,
    open: Array<Record<string, unknown>>,
    after: Array<Record<string, unknown>>,
  ) {
    const broker = fakeBroker({ positions: before });
    const { live, events } = port(broker, 200, 10);
    live.start();
    await live.submitEntry(entry());
    setPositions(broker, open);
    broker.emitOrder({ orderId: 'SUPER-1', correlationId: 'ENT-1', status: 'TRADED', tradedQty: 75, averageTradedPrice: 101, securityId: '48001', raw: {} });
    await settle();
    setPositions(broker, after);
    await new Promise<void>((resolve) => setTimeout(resolve, 50));
    await live.close();
    return events.find((event) => event.kind === 'PROTECTIVE_EXIT_FILLED') as Extract<ExecutionEvent, { kind: 'PROTECTIVE_EXIT_FILLED' }> | undefined;
  }

  it('should price a close from this trade only when the contract was already traded today', async () => {
    // Earlier today: bought 75 @ 100, sold 75 @ 120. This trade: bought 75 @ 101, stopped out 75 @ 70.
    const earlier = dayTotals(75, 7_500, 75, 9_000);
    const close = await bracketCloseAfter(
      [brokerRow(0, earlier)],
      [brokerRow(75, dayTotals(150, 15_075, 75, 9_000))],
      [brokerRow(0, dayTotals(150, 15_075, 150, 14_250))],
    );
    assert.equal(close?.quantity, 75);
    assert.equal(close?.averagePrice, 70, 'not the blended day average of 95');
  });

  it('should ignore a position in the same contract held under another product', async () => {
    const manual = { ...brokerRow(75, dayTotals(75, 7_500, 0, 0)), productType: 'MARGIN' };
    const close = await bracketCloseAfter(
      [manual],
      [manual, brokerRow(75, dayTotals(75, 7_575, 0, 0))],
      [manual, brokerRow(0, dayTotals(75, 7_575, 75, 12_150))],
    );
    assert.equal(close?.averagePrice, 162, 'the INTRADAY row is read, and its bracket close is seen');
  });

  it('should book a close with no visible sell at the stop price, not as a total loss', async () => {
    const close = await bracketCloseAfter([], [brokerRow(75)], [brokerRow(0)]);
    assert.equal(close?.averagePrice, 70.05);
    assert.equal(close?.quantity, 75);
  });

  it('should still enter when the positions read before the entry fails', async () => {
    const broker = fakeBroker({ positionsError: new Error('read timeout') });
    const { live } = port(broker);
    await live.submitEntry(entry());
    assert.equal(broker.calls.superPlace.length, 1);
    await live.close();
  });
});

describe('LiveExecutionPort reconciliation', () => {
  it('reports an external (bracket) close seen only in positions, exactly once', async () => {
    const broker = fakeBroker({ positions: [brokerRow(75)] });
    const { live, events } = port(broker, 200, 10);
    live.start();
    await live.submitEntry(entry());
    broker.emitOrder({ orderId: 'SUPER-1', correlationId: 'ENT-1', status: 'TRADED', tradedQty: 75, averageTradedPrice: 101, securityId: '48001', raw: {} });
    await settle();
    setPositions(broker, [brokerRow(0, dayTotals(75, 7575, 75, 12_150))]);
    await new Promise<void>((resolve) => setTimeout(resolve, 50));
    const closes = events.filter((event) => event.kind === 'PROTECTIVE_EXIT_FILLED');
    assert.equal(closes.length, 1);
    assert.equal(closes[0]?.kind === 'PROTECTIVE_EXIT_FILLED' && closes[0].averagePrice, 162);
    await live.close();
  });

  it('turns an unconfirmed entry that shows up at the broker into a late ENTRY_FILLED once', async () => {
    const broker = fakeBroker({ placeError: new ApiResponseError('gateway timeout', 504) });
    const { live, events } = port(broker, 200, 10);
    live.start();
    await live.submitEntry(entry());
    setPositions(broker, [brokerRow(75, dayTotals(75, 7_590, 0, 0))]);
    await new Promise<void>((resolve) => setTimeout(resolve, 60));
    const fills = events.filter((event) => event.kind === 'ENTRY_FILLED');
    assert.equal(fills.length, 1);
    assert.equal(fills[0]?.kind === 'ENTRY_FILLED' && fills[0].averagePrice, 101.2);
    assert.equal(events[0]?.kind, 'ENTRY_UNCONFIRMED');
    await live.close();
  });
});

describe('LiveExecutionPort exit resilience (review 2026-11-10)', () => {
  const FILLED_ENTRY = { orderId: 'SUPER-1', correlationId: 'ENT-1', status: 'TRADED', tradedQty: 75, averageTradedPrice: 101, securityId: '48001', raw: {} };

  /** Positions reads that fail `failures` times, then return `rows`. */
  function flakyPositions(broker: ReturnType<typeof fakeBroker>, failures: number, rows: Array<Record<string, unknown>>): void {
    let remaining = failures;
    (broker.client as unknown as { positions: { list: () => Promise<unknown[]> } }).positions.list = async () => {
      if (remaining > 0) {
        remaining -= 1;
        throw new Error('read timeout');
      }
      return rows;
    };
  }

  it('should still exit when one positions read fails and the next succeeds', async () => {
    const broker = fakeBroker({ positions: [brokerRow(75)] });
    const { live, events } = port(broker);
    await live.submitEntry(entry());
    broker.emitOrder(FILLED_ENTRY);
    await settle();
    flakyPositions(broker, 1, [brokerRow(75)]);
    await live.submitExit(exit());
    assert.equal(broker.calls.place.length, 1, 'a single failed read must not strand the position');
    assert.notEqual(events.at(-1)?.kind, 'EXIT_UNCONFIRMED');
    await live.close();
  });

  it('should not treat a tracked position missing from the broker list as flat on the exit path', async () => {
    const broker = fakeBroker({ positions: [brokerRow(75)] });
    const { live, events } = port(broker);
    await live.submitEntry(entry());
    broker.emitOrder(FILLED_ENTRY);
    await settle();
    setPositions(broker, []);
    await live.submitExit(exit());
    assert.equal(broker.calls.place.length, 0);
    assert.equal(broker.calls.superCancel.length, 0, 'the legs keep protecting a position that cannot be read');
    assert.equal(events.at(-1)?.kind, 'EXIT_UNCONFIRMED');
    assert.equal(events.some((event) => event.kind === 'PROTECTIVE_EXIT_FILLED'), false);
    await live.close();
  });

  it('should not book a close when the position row is missing from one reconciliation read', async () => {
    const broker = fakeBroker({ positions: [brokerRow(75)] });
    const { live, events } = port(broker, 200, 10);
    live.start();
    await live.submitEntry(entry());
    broker.emitOrder(FILLED_ENTRY);
    await settle();
    let reads = 0;
    (broker.client as unknown as { positions: { list: () => Promise<unknown[]> } }).positions.list = async () => {
      reads += 1;
      return reads === 1 ? [] : [brokerRow(75)];
    };
    await new Promise<void>((resolve) => setTimeout(resolve, 80));
    assert.ok(reads >= 3);
    assert.equal(events.some((event) => event.kind === 'PROTECTIVE_EXIT_FILLED'), false, 'one partial response is not a close');
    await live.close();
  });

  it('should book a close once the position row stays missing over consecutive reconciliation reads', async () => {
    const broker = fakeBroker({ positions: [brokerRow(75)] });
    const { live, events } = port(broker, 200, 10);
    live.start();
    await live.submitEntry(entry());
    broker.emitOrder(FILLED_ENTRY);
    await settle();
    setPositions(broker, []);
    await new Promise<void>((resolve) => setTimeout(resolve, 80));
    assert.equal(events.filter((event) => event.kind === 'PROTECTIVE_EXIT_FILLED').length, 1);
    await live.close();
  });

  it('should cancel a SELL that rests unfilled at the timeout and report it rejected, so the exit is retried', async () => {
    const broker = fakeBroker({ positions: [brokerRow(75)], sellOrderId: 'SELL-1' });
    const { live, events } = port(broker, 50);
    await live.submitEntry(entry());
    broker.emitOrder(FILLED_ENTRY);
    await settle();
    await live.submitExit(exit());
    await new Promise((resolve) => setTimeout(resolve, 70));
    assert.deepEqual(broker.calls.cancel, ['SELL-1'], 'the resting SELL is cancelled at the timeout');
    broker.emitOrder({ orderId: 'SELL-1', correlationId: 'EXT-1', status: 'CANCELLED', tradedQty: 0, securityId: '48001', raw: {} });
    await settle();
    assert.equal(events.at(-1)?.kind, 'EXIT_REJECTED');
    await live.submitExit({ ...exit(), correlationId: 'EXT-2' });
    assert.equal(broker.calls.place.length, 2, 'a cancelled SELL with no fill is definitive, so the retry is sent');
    await live.close();
  });

  it('should report a retryable rejection, not a halt, when the read after cancelling the legs fails', async () => {
    const broker = fakeBroker({ positions: [brokerRow(75)] });
    const { live, events } = port(broker);
    await live.submitEntry(entry());
    broker.emitOrder(FILLED_ENTRY);
    await settle();
    // The first read succeeds, then every read fails: the legs are cancelled and no SELL was sent.
    let reads = 0;
    (broker.client as unknown as { positions: { list: () => Promise<unknown[]> } }).positions.list = async () => {
      reads += 1;
      if (reads === 1) {
        return [brokerRow(75)];
      }
      throw new Error('read timeout');
    };
    await live.submitExit(exit());
    assert.equal(broker.calls.superCancel.length, 2);
    assert.equal(broker.calls.place.length, 0);
    assert.equal(events.at(-1)?.kind, 'EXIT_REJECTED', 'nothing was sent, and the position has no stop: the exit must be retried');

    // The retry also cannot read the position. It still must not halt, because the legs are gone.
    await live.submitExit({ ...exit(), correlationId: 'EXT-2' });
    assert.equal(events.at(-1)?.kind, 'EXIT_REJECTED');

    setPositions(broker, [brokerRow(75)]);
    await live.submitExit({ ...exit(), correlationId: 'EXT-3' });
    assert.equal(broker.calls.place.length, 1, 'the SELL goes out once the position can be read');
    assert.equal(broker.calls.place[0]?.['correlationId'], 'EXT-3');
    await live.close();
  });

  it('should keep cancelling a resting SELL from reconciliation and release the exit once the order book shows it cancelled', async () => {
    let status = 'PENDING';
    const options: Parameters<typeof fakeBroker>[0] = {
      positions: [brokerRow(75)],
      sellOrderId: 'SELL-1',
      orderCancelError: new Error('cancel timeout'),
      orderByCorrelationId: () => ({ orderId: 'SELL-1', correlationId: 'EXT-1', orderStatus: status, filledQty: 0 }),
    };
    const broker = fakeBroker(options);
    const { live, events } = port(broker, 40, 10);
    live.start();
    await live.submitEntry(entry());
    broker.emitOrder(FILLED_ENTRY);
    await settle();
    await live.submitExit(exit());
    await new Promise((resolve) => setTimeout(resolve, 70));
    assert.equal(events.at(-1)?.kind, 'EXIT_UNCONFIRMED', 'a failed cancel leaves the SELL outcome unknown');

    // A second SELL is refused while the first may be live.
    await live.submitExit({ ...exit(), correlationId: 'EXT-2' });
    assert.equal(broker.calls.place.length, 1);

    // The broker recovers: reconciliation cancels the resting SELL, then reads it CANCELLED with no fill.
    delete options.orderCancelError;
    await new Promise((resolve) => setTimeout(resolve, 40));
    assert.ok(broker.calls.cancel.length >= 2, 'reconciliation retries the cancel');
    status = 'CANCELLED';
    await new Promise((resolve) => setTimeout(resolve, 40));
    const released = events.filter((event) => event.kind === 'EXIT_REJECTED');
    assert.equal(released.length, 1, 'a cancelled SELL with no fill is definitive');
    assert.equal(released[0]?.kind === 'EXIT_REJECTED' && released[0].correlationId, 'EXT-1');

    await live.submitExit({ ...exit(), correlationId: 'EXT-3' });
    assert.equal(broker.calls.place.length, 2, 'the exit is sent again');
    await live.close();
  });

  it('should keep a SELL unknown when the order book cannot be read or shows a fill', async () => {
    let row: Record<string, unknown> | undefined;
    const broker = fakeBroker({
      positions: [brokerRow(75)],
      sellError: new Error('socket hang up'),
      orderByCorrelationId: () => {
        if (row === undefined) {
          throw new Error('order book unavailable');
        }
        return row;
      },
    });
    const { live, events } = port(broker, 40, 10);
    live.start();
    await live.submitEntry(entry());
    broker.emitOrder(FILLED_ENTRY);
    await settle();
    await live.submitExit(exit());
    assert.equal(events.at(-1)?.kind, 'EXIT_UNCONFIRMED');
    await new Promise((resolve) => setTimeout(resolve, 40));
    assert.ok(broker.calls.orderReads.length >= 1);
    row = { orderId: 'SELL-9', correlationId: 'EXT-1', orderStatus: 'CANCELLED', filledQty: 25 };
    await new Promise((resolve) => setTimeout(resolve, 40));
    assert.equal(events.some((event) => event.kind === 'EXIT_REJECTED'), false, 'a partial fill is never released for a resend');
    await live.submitExit({ ...exit(), correlationId: 'EXT-2' });
    assert.equal(broker.calls.place.length, 1, 'no second SELL while the first is unresolved');
    await live.close();
  });
});

describe('LiveExecutionPort protection and the broker P&L exit', () => {
  it('reports the protection as exchange-held', () => {
    const { live } = port(fakeBroker());
    assert.equal(live.protection, 'EXCHANGE_BRACKET');
  });

  it('arms the broker P&L exit before the entry, without the kill switch', async () => {
    const broker = fakeBroker();
    const { live } = port(broker);
    await live.armBrokerPnlExit(3_000);
    await live.submitEntry(entry());
    await settle();
    assert.deepEqual(broker.calls.pnlExit, [{ lossValue: 3_000, enableKillSwitch: false, productType: ['INTRADAY'] }]);
    assert.equal(broker.calls.superPlace.length, 1, 'the entry went out after the arm');
  });

  it('does not resend an ambiguous arming outcome, and refuses every entry as unconfirmed', async () => {
    const broker = fakeBroker({ pnlExitFailures: [new Error('socket hang up')] });
    const { live, events } = port(broker);
    await live.armBrokerPnlExit(3_000);
    await live.submitEntry(entry('ENT-1'));
    await live.submitEntry(entry('ENT-2'));
    await settle();
    const seen = events as Array<{ kind: string; reason?: string }>;
    assert.deepEqual(
      seen.map((event) => event.kind),
      ['ENTRY_UNCONFIRMED', 'ENTRY_UNCONFIRMED'],
      'each entry is refused as unconfirmed, because the broker P&L exit outcome is unknown',
    );
    assert.match(seen[0]?.reason ?? '', /P&L exit/);
    assert.equal(broker.calls.superPlace.length, 0, 'the entry never reached Dhan');
    assert.equal(broker.calls.pnlExit.length, 1, 'the ambiguous call is never resent (ADR-005)');
  });

  it('retries a refused arming on the next entry, and sends the entry once it is armed', async () => {
    const broker = fakeBroker({ pnlExitFailures: [new ApiResponseError('loss value out of range', 400)] });
    const { live, events } = port(broker);
    await live.armBrokerPnlExit(3_000);
    await live.submitEntry(entry());
    await settle();
    assert.equal(broker.calls.pnlExit.length, 2, 'a definitive refusal was not applied, so one retry per entry is safe');
    assert.equal(broker.calls.superPlace.length, 1, 'the entry went out once the retry armed the exit');
    assert.equal((events as Array<{ kind: string }>).filter((event) => event.kind === 'ENTRY_REJECTED').length, 0);
  });

  it('sends no broker P&L exit unless the feature was armed', async () => {
    const broker = fakeBroker();
    const { live } = port(broker);
    await live.submitEntry(entry());
    await settle();
    assert.equal(broker.calls.pnlExit.length, 0);
  });
});
