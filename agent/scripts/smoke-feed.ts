/**
 * Read-only WebSocket smoke test: connects the Dhan market feed, subscribes to index spots,
 * and reports raw vs parsed vs routed tick counts. Places no orders.
 *
 *   npm run smoke:feed
 */
import 'dotenv/config';
import { loadConfig } from '../src/config.js';
import { createDhanClient } from '../src/dhan/client.js';
import { asPriceEvent, DhanFeed } from '../src/dhan/feed.js';
import { InstrumentMaster } from '../src/dhan/instrumentMaster.js';
import { createConsoleLogger } from '../src/ops/logger.js';
import { istParts } from '../src/time/ist.js';

const WAIT_MS = Number(process.env['SMOKE_FEED_WAIT_MS'] ?? 20_000);

async function main(): Promise<void> {
  const config = loadConfig({ ...process.env, MODE: 'paper' });
  const logger = createConsoleLogger();
  const client = await createDhanClient(config.dhan, { logger });
  const master = new InstrumentMaster(client.instruments, () => istParts(Date.now()).date);

  const spots: { symbol: string; ref: Awaited<ReturnType<InstrumentMaster['resolveSpot']>> }[] = [];
  for (const underlying of config.underlyings) {
    const ref = await master.resolveSpot(underlying.symbol);
    spots.push({ symbol: underlying.symbol, ref });
    console.log(`spot ${underlying.symbol}: ${ref.exchangeSegment}:${ref.securityId}`);
  }

  let raw = 0;
  let parsed = 0;
  let routed = 0;
  const sampleRaw: unknown[] = [];

  client.ws.market.on('open', () => console.log('ws: market socket open'));
  client.ws.market.on('close', () => console.log('ws: market socket closed'));
  client.ws.market.on('disconnect', (event: unknown) => console.log('ws: server disconnect frame', JSON.stringify(event).slice(0, 200)));

  const feed = new DhanFeed(client, {
    istShiftedTimestamps: config.feed.feedIstShifted,
    marketFeedMode: config.feed.marketFeedMode,
    logger,
  });

  client.ws.market.on('tick', (value: unknown) => {
    raw += 1;
    if (sampleRaw.length < 5) {
      sampleRaw.push(value);
    }
    if (asPriceEvent(value) !== undefined) {
      parsed += 1;
    }
  });

  feed.onTick(() => {
    routed += 1;
  });

  try {
    const ltp = await client.marketFeed.ltp({
      IDX_I: spots.map((row) => row.ref.securityId),
    });
    console.log('rest: marketfeed/ltp', JSON.stringify(ltp));
  } catch (error) {
    console.error('rest: marketfeed/ltp failed', error instanceof Error ? error.message : error);
  }

  await feed.start();
  console.log(`feed: started (market.connect resolved), mode=${config.feed.marketFeedMode}`);
  feed.subscribe(spots.map((row) => row.ref));
  console.log(`feed: subscribed to ${spots.length} index instruments; waiting ${WAIT_MS}ms…`);

  await new Promise((resolve) => setTimeout(resolve, WAIT_MS));

  console.log('summary:', { mode: config.feed.marketFeedMode, rawPackets: raw, parsedPriceEvents: parsed, feedRoutedTicks: routed });
  if (sampleRaw.length > 0) {
    console.log('sample raw ticks:');
    for (const row of sampleRaw) {
      console.log(JSON.stringify(row));
    }
  }

  feed.stop();
  if (raw === 0) {
    console.error('FAIL: no WebSocket packets in the wait window (check session hours, market-data access, or feed errors above)');
    process.exitCode = 1;
  } else if (parsed === 0) {
    console.error('FAIL: packets arrived but none matched asPriceEvent (parser mismatch)');
    process.exitCode = 1;
  } else if (routed === 0) {
    console.error('FAIL: parsed ticks did not match feed subscriptions (segment/securityId key mismatch)');
    process.exitCode = 1;
  } else {
    console.log('PASS: live index ticks are reaching the agent feed path');
  }
}

main().catch((error: unknown) => {
  console.error('fatal:', error instanceof Error ? error.message : error);
  process.exitCode = 1;
});
