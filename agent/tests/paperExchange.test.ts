import { strict as assert } from 'node:assert';
import { describe, it } from 'node:test';
import { PaperExchangeClient } from '../src/paper/exchangeClient.js';
import { PaperExchangeGateway } from '../src/paper/exchangeGateway.js';
import type { GatewayOrder } from '../src/execution/orderGateway.js';
import { createConsoleLogger } from '../src/ops/logger.js';
import { contract, istEpoch } from './support/fixtures.js';

const NOW = istEpoch('2026-10-12', '10:00');
const SILENT = createConsoleLogger(() => undefined, () => NOW);
const KEY = 'k-test-operator-key';
const BASE = 'http://127.0.0.1:3100';
const ORDER: GatewayOrder = {
  correlationId: 'ENT-1',
  side: 'BUY',
  contract: contract({ optionType: 'CE', strike: 22_450, securityId: '48001' }),
  quantity: 75,
  referencePrice: 100,
  reason: undefined,
};

interface Call {
  method: string;
  url: string;
  headers: Record<string, string>;
  body: unknown;
}

/** A fetch that answers from a queue of responses, and records every request it receives. */
function fakeFetch(responses: Array<{ status: number; body?: unknown } | Error>): { fetch: typeof fetch; calls: Call[] } {
  const calls: Call[] = [];
  const queue = [...responses];
  const impl = (async (input: string | URL | Request, init?: RequestInit) => {
    calls.push({
      method: init?.method ?? 'GET',
      url: String(input),
      headers: { ...(init?.headers as Record<string, string>) },
      body: init?.body === undefined ? undefined : JSON.parse(String(init.body)),
    });
    const next = queue.shift();
    if (next === undefined) {
      throw new Error('no scripted response left');
    }
    if (next instanceof Error) {
      throw next;
    }
    return new Response(next.body === undefined ? '' : JSON.stringify(next.body), { status: next.status });
  }) as typeof fetch;
  return { fetch: impl, calls };
}

function client(fetchImpl: typeof fetch): PaperExchangeClient {
  return new PaperExchangeClient({ baseUrl: BASE, apiKey: KEY, accountId: 'paper-1', timeoutMs: 1_000, fetch: fetchImpl });
}

const order = (id: number, status: string, filled = 0) => ({ id, client_order_id: 'ENT-1', status, filled_quantity: filled });
const trade = (orderId: number, quantity: number, price: number) => ({
  event_type: 'TRADE',
  payload: { order_id: orderId, quantity, price },
});

describe('PaperExchangeClient', () => {
  it('sends the API key and account on every request, and reads the available balance', async () => {
    const { fetch: impl, calls } = fakeFetch([{ status: 200, body: { available_balance: 250_000.5 } }]);
    assert.equal(await client(impl).availableBalance(), 250_000.5);
    assert.equal(calls[0]?.headers['X-API-Key'], KEY);
    assert.equal(calls[0]?.headers['X-Account-Id'], 'paper-1');
    assert.equal(calls[0]?.url, `${BASE}/api/account`);
  });

  it('refuses a placement the server answers with a 4xx as rejected, and a 5xx as unconfirmed', async () => {
    const refused = fakeFetch([{ status: 422, body: { error: 'Insufficient margin' } }]);
    await assert.rejects(client(refused.fetch).placeOrder({ quantity: 75 }), (error: Error & { failure?: string }) => error.failure === 'REJECTED');
    const broken = fakeFetch([{ status: 500, body: { error: 'Internal error' } }]);
    await assert.rejects(client(broken.fetch).placeOrder({ quantity: 75 }), (error: Error & { failure?: string }) => error.failure === 'UNCONFIRMED');
  });

  it('treats a timeout and a rate limit as unconfirmed, because the server may have acted', async () => {
    const timedOut = fakeFetch([new Error('The operation was aborted')]);
    await assert.rejects(client(timedOut.fetch).placeOrder({}), (error: Error & { failure?: string }) => error.failure === 'UNCONFIRMED');
    const limited = fakeFetch([{ status: 429, body: { error: 'slow down' } }]);
    await assert.rejects(client(limited.fetch).placeOrder({}), (error: Error & { failure?: string }) => error.failure === 'UNCONFIRMED');
  });

  it('never puts the API key in an error message', async () => {
    const { fetch: impl } = fakeFetch([{ status: 401, body: { error: `bad key ${KEY}` } }, { status: 500 }]);
    await assert.rejects(client(impl).availableBalance(), (error: Error) => {
      assert.ok(!error.message.includes(KEY));
      return true;
    });
  });
});

describe('PaperExchangeGateway', () => {
  it('sends a market order priced at the reference premium, and a sell as reduce-only', async () => {
    const { fetch: impl, calls } = fakeFetch([
      { status: 201, body: order(7, 'filled', 75) },
      { status: 200, body: { data: [trade(7, 75, 101)], next_cursor: null } },
      { status: 201, body: order(8, 'filled', 75) },
      { status: 200, body: { data: [trade(8, 75, 118)], next_cursor: null } },
    ]);
    const gateway = new PaperExchangeGateway(client(impl), { logger: SILENT });
    await gateway.place(ORDER);
    await gateway.place({ ...ORDER, side: 'SELL', correlationId: 'EXT-1', referencePrice: 120, reason: 'MANUAL' });
    const entryBody = calls[0]?.body as Record<string, unknown>;
    assert.equal(entryBody['order_type'], 'market');
    assert.equal(entryBody['execution_price'], 100);
    assert.equal(entryBody['reduce_only'], false);
    assert.equal(entryBody['client_order_id'], 'ENT-1');
    assert.equal((calls[2]?.body as Record<string, unknown>)['reduce_only'], true, 'an exit can only reduce the position');
  });

  it('reports a fill at the price from its TRADE ledger entry, found on a later page', async () => {
    const { fetch: impl } = fakeFetch([
      { status: 201, body: order(7, 'filled', 75) },
      { status: 200, body: { data: [{ event_type: 'MARGIN_LOCKED', payload: {} }], next_cursor: 'c1' } },
      { status: 200, body: { data: [trade(7, 50, 100), trade(9, 25, 90)], next_cursor: null } },
    ]);
    const outcome = await new PaperExchangeGateway(client(impl), { logger: SILENT }).place(ORDER);
    assert.deepEqual(outcome, { kind: 'FILLED', filledQuantity: 50, averagePrice: 100 });
  });

  it('nets charges into the fill, so the agent P&L matches the server wallet', async () => {
    const buy = fakeFetch([
      { status: 201, body: order(7, 'filled', 75) },
      { status: 200, body: { data: [{ event_type: 'TRADE', payload: { order_id: 7, quantity: 75, price: 100, charges: { total: 30 } } }], next_cursor: null } },
    ]);
    assert.deepEqual(await new PaperExchangeGateway(client(buy.fetch), { logger: SILENT }).place(ORDER), {
      kind: 'FILLED',
      filledQuantity: 75,
      averagePrice: (7500 + 30) / 75,
    });
    const sell = fakeFetch([
      { status: 201, body: order(8, 'filled', 75) },
      { status: 200, body: { data: [{ event_type: 'TRADE', payload: { order_id: 8, quantity: 75, price: 120, charges: { total: 30 } } }], next_cursor: null } },
    ]);
    const outcome = await new PaperExchangeGateway(client(sell.fetch), { logger: SILENT }).place({ ...ORDER, side: 'SELL', correlationId: 'EXT-1', referencePrice: 120, reason: 'MANUAL' });
    assert.deepEqual(outcome, { kind: 'FILLED', filledQuantity: 75, averagePrice: (9000 - 30) / 75 });
  });

  it('treats an API key refusal as unconfirmed, so a bad key halts the agent rather than rejecting every entry', async () => {
    const { fetch: impl } = fakeFetch([{ status: 401, body: { error: 'unauthorized' } }]);
    const outcome = await new PaperExchangeGateway(client(impl), { logger: SILENT }).place(ORDER);
    assert.equal(outcome.kind, 'UNCONFIRMED');
  });

  it('is unconfirmed when the server says filled but the trade is not in the ledger', async () => {
    const responses = Array.from({ length: 20 }, () => ({ status: 200, body: { data: [], next_cursor: 'more' } }));
    const { fetch: impl } = fakeFetch([{ status: 201, body: order(7, 'filled', 75) }, ...responses]);
    const outcome = await new PaperExchangeGateway(client(impl), { logger: SILENT }).place(ORDER);
    assert.equal(outcome.kind, 'UNCONFIRMED');
  });

  it('cancels an order that is not filled at the execution price, and reports it rejected', async () => {
    const { fetch: impl, calls } = fakeFetch([{ status: 201, body: order(7, 'open') }, { status: 200, body: order(7, 'cancelled') }]);
    const outcome = await new PaperExchangeGateway(client(impl), { logger: SILENT }).place(ORDER);
    assert.equal(outcome.kind, 'REJECTED');
    assert.equal(calls[1]?.method, 'DELETE');
    assert.equal(calls[1]?.url, `${BASE}/api/orders/7`);
  });

  it('reads the order back when the cancel conflicts with a fill that happened meanwhile', async () => {
    const { fetch: impl } = fakeFetch([
      { status: 201, body: order(7, 'open') },
      { status: 409, body: { error: 'cannot cancel a filled order' } },
      { status: 200, body: order(7, 'filled', 75) },
      { status: 200, body: { data: [trade(7, 75, 101)], next_cursor: null } },
    ]);
    const outcome = await new PaperExchangeGateway(client(impl), { logger: SILENT }).place(ORDER);
    assert.deepEqual(outcome, { kind: 'FILLED', filledQuantity: 75, averagePrice: 101 });
  });

  it('is unconfirmed on a status the agent does not know, and on a placement the server never answered', async () => {
    const unknown = fakeFetch([{ status: 201, body: order(7, 'routed') }]);
    assert.equal((await new PaperExchangeGateway(client(unknown.fetch), { logger: SILENT }).place(ORDER)).kind, 'UNCONFIRMED');
    const lost = fakeFetch([new Error('reset')]);
    assert.equal((await new PaperExchangeGateway(client(lost.fetch), { logger: SILENT }).place(ORDER)).kind, 'UNCONFIRMED');
  });

  it('counts non-zero positions on the account for the start check', async () => {
    const { fetch: impl } = fakeFetch([
      { status: 200, body: [{ id: 1, symbol: 'NIFTY', net_quantity: 75 }, { id: 2, symbol: 'RELIANCE', net_quantity: 0 }] },
    ]);
    assert.equal(await new PaperExchangeGateway(client(impl), { logger: SILENT }).openPositionCount(), 1);
  });
});
