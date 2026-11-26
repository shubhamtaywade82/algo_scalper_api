import { strict as assert } from 'node:assert';
import { describe, it } from 'node:test';
import { correlationIdFor } from '../src/execution/brokerIds.js';
import { GatewayExecutionPort } from '../src/execution/gatewayPort.js';
import type { ExecutionEvent } from '../src/execution/ports.js';
import { PaperExchangeClient } from '../src/paper/exchangeClient.js';
import { PaperExchangeGateway } from '../src/paper/exchangeGateway.js';
import { createConsoleLogger } from '../src/ops/logger.js';
import { contract, istEpoch } from './support/fixtures.js';

/**
 * End-to-end against a running paper_exchange server. Skipped unless all three variables are set:
 *
 *   PAPER_EXCHANGE_E2E_URL      e.g. http://127.0.0.1:3100
 *   PAPER_EXCHANGE_E2E_API_KEY  the server's PAPER_EXCHANGE_API_KEY
 *   PAPER_EXCHANGE_E2E_ACCOUNT  an INR account with enough margin for one NIFTY lot at ~100 (about 10,000)
 *
 * The test places real orders on that account. Each run uses fresh correlation ids, because the server returns the
 * existing order for a repeated client_order_id. Assertions compare against what the server reports, not fixed prices,
 * because charges move the fill away from the reference premium.
 */
const URL_ = process.env['PAPER_EXCHANGE_E2E_URL'];
const KEY = process.env['PAPER_EXCHANGE_E2E_API_KEY'];
const ACCOUNT = process.env['PAPER_EXCHANGE_E2E_ACCOUNT'];
const SKIP = URL_ === undefined || KEY === undefined || ACCOUNT === undefined;
const SILENT = createConsoleLogger(() => undefined, () => Date.now());
const EXPIRY = '2026-10-29';

function client(apiKey = KEY ?? ''): PaperExchangeClient {
  return new PaperExchangeClient({ baseUrl: URL_ ?? '', apiKey, accountId: ACCOUNT ?? '', timeoutMs: 5_000 });
}

function option(strike: number) {
  return contract({ optionType: 'CE', strike, securityId: `E2E${strike}`, expiry: EXPIRY });
}

/** Polls until the condition holds or five seconds pass. Events arrive after a network round trip, so a fixed wait would be flaky. */
async function waitFor(condition: () => boolean): Promise<void> {
  const deadline = Date.now() + 5_000;
  while (!condition() && Date.now() < deadline) {
    await new Promise<void>((resolve) => setTimeout(resolve, 50));
  }
}

function uniqueId(kind: 'E' | 'X' | 'P'): string {
  return correlationIdFor(kind, Date.now(), Math.floor(Math.random() * 1_000_000));
}

describe('paper_exchange end to end', { skip: SKIP }, () => {
  it('reads an INR account with a usable balance', async () => {
    const account = await client().account();
    assert.equal(account.currency, 'INR');
    assert.ok(account.availableBalance > 0);
  });

  it('refuses a wrong API key without placing anything, and the refusal halts rather than rejects', async () => {
    const gateway = new PaperExchangeGateway(client('not-the-key'), { logger: SILENT });
    const outcome = await gateway.place({
      correlationId: uniqueId('E'),
      side: 'BUY',
      contract: option(22_450),
      quantity: 75,
      referencePrice: 100,
      reason: undefined,
    });
    assert.equal(outcome.kind, 'UNCONFIRMED');
  });

  it('fills an entry at the reference premium plus charges, and a sell at the premium less charges', async () => {
    const gateway = new PaperExchangeGateway(client(), { logger: SILENT });
    const strike = 22_450;
    const entryId = uniqueId('E');
    const entry = await gateway.place({ correlationId: entryId, side: 'BUY', contract: option(strike), quantity: 75, referencePrice: 100, reason: undefined });
    assert.equal(entry.kind, 'FILLED');
    if (entry.kind !== 'FILLED') {
      return;
    }
    assert.equal(entry.filledQuantity, 75);
    assert.ok(entry.averagePrice > 100 && entry.averagePrice < 102, `buy average ${entry.averagePrice} carries charges above 100`);

    const exit = await gateway.place({ correlationId: uniqueId('X'), side: 'SELL', contract: option(strike), quantity: 75, referencePrice: 120, reason: 'MANUAL' });
    assert.equal(exit.kind, 'FILLED');
    if (exit.kind !== 'FILLED') {
      return;
    }
    assert.ok(exit.averagePrice < 120 && exit.averagePrice > 118, `sell average ${exit.averagePrice} is below 120 by charges`);
  });

  it('runs the agent path end to end: entry through the port, then the target sold by the agent', async () => {
    const gateway = new PaperExchangeGateway(client(), { logger: SILENT });
    const events: ExecutionEvent[] = [];
    const port = new GatewayExecutionPort(gateway, { mode: 'paper', logger: SILENT, now: () => Date.now() });
    port.onEvent((event) => events.push(event));
    // The account may hold positions from earlier runs, so the check is that this run leaves the count as it found it.
    const openBefore = await port.openPositionCount();
    const correlationId = uniqueId('E');
    await port.submitEntry({
      side: 'BUY',
      correlationId,
      underlying: 'NIFTY',
      contract: option(22_500),
      quantity: 75,
      entryReference: 100,
      stopLossPrice: 70,
      targetPrice: 130,
    });
    port.onOptionTick({ exchangeSegment: 'NSE_FNO', securityId: 'E2E22500', ltp: 131, ltt: Date.now() });
    await waitFor(() => events.some((event) => event.kind === 'PROTECTIVE_EXIT_FILLED' || event.kind === 'BROKER_MISMATCH'));
    assert.equal(events[0]?.kind, 'ENTRY_FILLED');
    const exit = events.find((event) => event.kind === 'PROTECTIVE_EXIT_FILLED');
    assert.equal(exit?.kind === 'PROTECTIVE_EXIT_FILLED' && exit.reason, 'TARGET');
    assert.equal(await port.openPositionCount(), openBefore, 'this run leaves no open position behind');
  });

  it('returns the same order for a repeated client_order_id, so a retry cannot double a fill', async () => {
    const id = uniqueId('E');
    const body = {
      client_order_id: id,
      symbol: 'NIFTY',
      side: 'buy',
      quantity: 75,
      order_type: 'market',
      instrument_type: 'OPTIDX',
      option_type: 'CE',
      strike_price: 22_550,
      expiry_date: EXPIRY,
      exchange_segment: 'NSE_FNO',
      execution_price: 100,
      reduce_only: false,
    };
    const first = await client().placeOrder(body);
    const second = await client().placeOrder(body);
    assert.equal(second.id, first.id);
    assert.equal(first.status, 'filled');
    // Close what this test opened, so no position is left open behind it.
    const gateway = new PaperExchangeGateway(client(), { logger: SILENT });
    const close = await gateway.place({ correlationId: uniqueId('X'), side: 'SELL', contract: option(22_550), quantity: 75, referencePrice: 100, reason: 'MANUAL' });
    assert.equal(close.kind, 'FILLED');
  });

  it('rejects a reduce-only sell with nothing to reduce, and sends nothing that opens a short', async () => {
    const gateway = new PaperExchangeGateway(client(), { logger: SILENT });
    const outcome = await gateway.place({
      correlationId: uniqueId('X'),
      side: 'SELL',
      contract: option(22_600),
      quantity: 75,
      referencePrice: 120,
      reason: 'MANUAL',
    });
    assert.equal(outcome.kind, 'REJECTED');
  });
});
