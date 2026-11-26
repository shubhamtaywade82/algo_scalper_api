import { strict as assert } from 'node:assert';
import { describe, it } from 'node:test';
import { ApiResponseError } from '@nemesis-oss/dhanhq-sdk';
import { DhanSandboxGateway, type SandboxClient } from '../src/dhan/sandboxGateway.js';
import type { GatewayOrder } from '../src/execution/orderGateway.js';
import { createConsoleLogger } from '../src/ops/logger.js';
import { contract, istEpoch } from './support/fixtures.js';

const NOW = istEpoch('2026-10-12', '10:00');
const SILENT = createConsoleLogger(() => undefined, () => NOW);
const ORDER: GatewayOrder = {
  correlationId: 'ENT-1',
  side: 'BUY',
  contract: contract({ optionType: 'CE', strike: 22_450, securityId: '48001' }),
  quantity: 75,
  referencePrice: 100,
  reason: undefined,
};

interface Reading {
  orderStatus?: string;
  filledQty?: number;
  averageTradedPrice?: number;
}

/**
 * A sandbox that returns scripted readings for one order. The clock advances on every sleep, so the order timeout is
 * exercised without real waiting.
 */
function sandbox(options: { placeError?: Error; readings: Reading[]; cancelError?: Error }): { client: SandboxClient; cancels: string[]; clock: { now: number } } {
  const clock = { now: NOW };
  const cancels: string[] = [];
  let index = 0;
  const client = {
    orders: {
      place: async () => {
        if (options.placeError !== undefined) {
          throw options.placeError;
        }
        return { correlationId: 'ENT-1', data: { orderId: 'SBX-1' } };
      },
      getById: async () => {
        const reading = options.readings[Math.min(index, options.readings.length - 1)] ?? {};
        index += 1;
        return { orderId: 'SBX-1', ...reading };
      },
      cancel: async (orderId: string) => {
        cancels.push(orderId);
        if (options.cancelError !== undefined) {
          throw options.cancelError;
        }
        return { orderId };
      },
    },
    positions: {
      list: async () => [
        { exchangeSegment: 'NSE_FNO', netQty: 75 },
        { exchangeSegment: 'NSE_EQ', netQty: 10 },
        { exchangeSegment: 'NSE_FNO', netQty: 0 },
      ],
    },
  } as unknown as SandboxClient;
  return { client, cancels, clock };
}

function gateway(client: SandboxClient, clock: { now: number }, orderTimeoutMs = 3_000): DhanSandboxGateway {
  return new DhanSandboxGateway(client, {
    orderTimeoutMs,
    pollIntervalMs: 500,
    logger: SILENT,
    now: () => clock.now,
    sleep: async (ms) => {
      clock.now += ms;
    },
  });
}

describe('DhanSandboxGateway', () => {
  it('reports a fill once the sandbox has traded the order, with its own fill price', async () => {
    const { client, clock } = sandbox({ readings: [{ orderStatus: 'PENDING' }, { orderStatus: 'TRADED', filledQty: 75, averageTradedPrice: 101.5 }] });
    assert.deepEqual(await gateway(client, clock).place(ORDER), { kind: 'FILLED', filledQuantity: 75, averagePrice: 101.5 });
  });

  it('reports a sandbox rejection as rejected, and a placement the sandbox never answered as unconfirmed', async () => {
    const rejected = sandbox({ placeError: new ApiResponseError('quantity not in lot size', 400), readings: [] });
    assert.equal((await gateway(rejected.client, rejected.clock).place(ORDER)).kind, 'REJECTED');
    const unanswered = sandbox({ placeError: new Error('socket hang up'), readings: [] });
    assert.equal((await gateway(unanswered.client, unanswered.clock).place(ORDER)).kind, 'UNCONFIRMED');
  });

  it('reports a sandbox order that was rejected or cancelled before filling as rejected', async () => {
    const { client, clock } = sandbox({ readings: [{ orderStatus: 'REJECTED' }] });
    assert.deepEqual(await gateway(client, clock).place(ORDER), { kind: 'REJECTED', reason: 'sandbox order REJECTED' });
  });

  it('never reports a fill without an average price, because the agent would have no entry to size its stop from', async () => {
    const { client, clock } = sandbox({ readings: [{ orderStatus: 'TRADED', filledQty: 75 }] });
    assert.equal((await gateway(client, clock).place(ORDER)).kind, 'UNCONFIRMED');
  });

  it('cancels an order still working at the deadline, and keeps the part that filled', async () => {
    const { client, cancels, clock } = sandbox({
      // Three reads while the order is still working, which exhausts the 1 s deadline. The read after the cancel is last.
      readings: [
        { orderStatus: 'PART_TRADED', filledQty: 25, averageTradedPrice: 100 },
        { orderStatus: 'PART_TRADED', filledQty: 25, averageTradedPrice: 100 },
        { orderStatus: 'PART_TRADED', filledQty: 25, averageTradedPrice: 100 },
        { orderStatus: 'CANCELLED', filledQty: 25, averageTradedPrice: 100 },
      ],
    });
    assert.deepEqual(await gateway(client, clock, 1_000).place(ORDER), { kind: 'FILLED', filledQuantity: 25, averagePrice: 100 });
    assert.deepEqual(cancels, ['SBX-1']);
  });

  it('is unconfirmed when the order is still working after the cancel and cannot be read back', async () => {
    const { client, clock } = sandbox({ readings: [{ orderStatus: 'PENDING' }], cancelError: new Error('cancel timed out') });
    const outcome = await gateway(client, clock, 1_000).place(ORDER);
    assert.equal(outcome.kind, 'UNCONFIRMED');
  });

  it('counts open option positions in the F&O segments only', async () => {
    const { client, clock } = sandbox({ readings: [] });
    assert.equal(await gateway(client, clock).openPositionCount(), 1);
  });
});
