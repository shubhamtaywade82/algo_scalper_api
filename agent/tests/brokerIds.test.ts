import { strict as assert } from 'node:assert';
import { describe, it } from 'node:test';
import { BROKER_CORRELATION_MAX, correlationIdFor, fitsBrokerLimit } from '../src/execution/brokerIds.js';
import { GatewayExecutionPort } from '../src/execution/gatewayPort.js';
import type { GatewayOrder, GatewayOutcome, OrderGateway } from '../src/execution/orderGateway.js';
import type { EntryOrder } from '../src/execution/ports.js';
import { createConsoleLogger } from '../src/ops/logger.js';
import { contract, istEpoch } from './support/fixtures.js';

const NOW = istEpoch('2026-10-12', '10:00');
const SILENT = createConsoleLogger(() => undefined, () => NOW);
const OPTION = contract({ optionType: 'CE', strike: 22_450, securityId: '48001', underlying: 'MIDCPNIFTY' });

describe('broker correlation ids', () => {
  it('stays within Dhan\'s 30-character limit at today\'s clock and a six-digit counter', () => {
    const now = Date.now();
    for (const kind of ['E', 'X', 'P'] as const) {
      const id = correlationIdFor(kind, now, 999_999);
      assert.ok(id.length <= BROKER_CORRELATION_MAX, `${kind} id is ${id.length} characters`);
      assert.ok(fitsBrokerLimit(id));
    }
  });

  it('gives each attempt its own id, even within one millisecond', () => {
    const ids = new Set([1, 2, 3].map((counter) => correlationIdFor('X', NOW, counter)));
    assert.equal(ids.size, 3);
  });

  it('refuses ids over the limit and empty ids', () => {
    assert.equal(fitsBrokerLimit('x'.repeat(31)), false);
    assert.equal(fitsBrokerLimit(''), false);
    assert.equal(fitsBrokerLimit('x'.repeat(30)), true);
  });

  it('rejects, without sending, an entry whose id is over the limit', async () => {
    const sent: GatewayOrder[] = [];
    const gateway: OrderGateway = {
      place: async (order): Promise<GatewayOutcome> => {
        sent.push(order);
        return { kind: 'FILLED', filledQuantity: 75, averagePrice: 100 };
      },
      openPositionCount: async () => 0,
    };
    const events: string[] = [];
    const port = new GatewayExecutionPort(gateway, { mode: 'sandbox', logger: SILENT, now: () => NOW });
    port.onEvent((event) => events.push(event.kind));
    const entry: EntryOrder = {
      side: 'BUY',
      correlationId: 'ENT-MIDCPNIFTY-LONG-ID-THAT-IS-TOO-LONG',
      underlying: 'MIDCPNIFTY',
      contract: OPTION,
      quantity: 75,
      entryReference: 100,
      stopLossPrice: 70,
      targetPrice: 160,
    };
    await port.submitEntry(entry);
    await new Promise<void>((resolve) => setImmediate(resolve));
    assert.deepEqual(events, ['ENTRY_REJECTED']);
    assert.equal(sent.length, 0, 'the oversize id never reached the venue');
  });

  it('sends the protective exit under a fresh id that fits the limit', async () => {
    const sent: GatewayOrder[] = [];
    const gateway: OrderGateway = {
      place: async (order): Promise<GatewayOutcome> => {
        sent.push(order);
        return order.side === 'BUY' ? { kind: 'FILLED', filledQuantity: 75, averagePrice: 100 } : { kind: 'FILLED', filledQuantity: 75, averagePrice: 60 };
      },
      openPositionCount: async () => 0,
    };
    const port = new GatewayExecutionPort(gateway, { mode: 'sandbox', logger: SILENT, now: () => NOW });
    await port.submitEntry({
      side: 'BUY',
      correlationId: correlationIdFor('E', NOW, 1),
      underlying: 'MIDCPNIFTY',
      contract: OPTION,
      quantity: 75,
      entryReference: 100,
      stopLossPrice: 70,
      targetPrice: 160,
    });
    port.onOptionTick({ exchangeSegment: 'NSE_FNO', securityId: '48001', ltp: 60, ltt: NOW });
    await new Promise<void>((resolve) => setImmediate(resolve));
    const protective = sent.at(-1);
    assert.equal(protective?.reason, 'STOP_LOSS');
    assert.ok(protective !== undefined && fitsBrokerLimit(protective.correlationId), 'the protective id fits the limit');
  });
});
