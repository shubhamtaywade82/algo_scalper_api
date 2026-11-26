import { strict as assert } from 'node:assert';
import { describe, it } from 'node:test';
import type { Instrument } from '@nemesis-oss/dhanhq-sdk';
import { asPriceEvent, DhanFeed, parseIndexPacket } from '../src/dhan/feed.js';
import { InstrumentMaster, normalizeExpiry, toOptionContract } from '../src/dhan/instrumentMaster.js';
import { DhanMarketData, intradayIntervalFor, mapChartColumns, OPTION_CHAIN_MIN_INTERVAL_MS } from '../src/dhan/marketData.js';
import { istEpoch } from './support/fixtures.js';

function row(overrides: Partial<Instrument>): Instrument {
  return { securityId: '48001', ...overrides } as unknown as Instrument;
}

const NIFTY_CALL = row({
  securityId: '48001',
  instrument: 'OPTIDX',
  underlyingSymbol: 'NIFTY',
  exchangeSegment: 'NSE_FNO',
  optionType: 'CE',
  strikePrice: 22_450,
  expiryDate: '2026-10-15 14:30:00',
  lotSize: 75,
  tickSize: 5,
  displayName: 'NIFTY 15 OCT 22450 CALL',
});

describe('chart mapping', () => {
  it('converts columns to ascending, de-duplicated bars on the true UTC instant', () => {
    const ts = [istEpoch('2026-10-12', '09:20') / 1000, istEpoch('2026-10-12', '09:15') / 1000, istEpoch('2026-10-12', '09:15') / 1000];
    const bars = mapChartColumns(
      { open: [1, 2, 3], high: [2, 3, 4], low: [0.5, 1, 2], close: [1.5, 2.5, 3.5], timestamp: ts },
      false,
    );
    assert.deepEqual(bars.map((bar) => bar.time), [istEpoch('2026-10-12', '09:15'), istEpoch('2026-10-12', '09:20')]);
    assert.equal(bars[0]?.volume, 0);
  });

  it('applies the IST shift only when the feed encodes IST wall-clock', () => {
    const wallClock = istEpoch('2026-10-12', '09:15') / 1000 + 19_800;
    const [bar] = mapChartColumns({ open: [1], high: [1], low: [1], close: [1], timestamp: [wallClock] }, true);
    assert.equal(bar?.time, istEpoch('2026-10-12', '09:15'));
  });

  it('drops bars outside the 09:15-15:30 session, as live bars do', () => {
    const inSession = istEpoch('2026-10-26', '15:25') / 1000;
    const afterClose = istEpoch('2026-10-26', '18:40') / 1000;
    const bars = mapChartColumns({ open: [1, 1], high: [1, 1], low: [1, 1], close: [1, 1], timestamp: [inSession, afterClose] }, false);
    assert.deepEqual(bars.map((bar) => bar.time), [inSession * 1000]);
  });

  it('fails the whole batch on mismatched columns or an impossible bar', () => {
    assert.throws(() => mapChartColumns({ open: [1, 2], high: [1], low: [1], close: [1], timestamp: [1] }, false), /mismatched/);
    assert.throws(() => mapChartColumns({ open: [1], high: [0.5], low: [1], close: [1], timestamp: [1] }, false), /invalid chart bar/);
    assert.throws(() => mapChartColumns({ open: [1], high: [1], low: [1], close: [1] }, false), /missing/);
  });

  it('accepts only the bar sizes Dhan intraday charts offer', () => {
    assert.equal(intradayIntervalFor(5), '5');
    assert.throws(() => intradayIntervalFor(3), /BAR_MINUTES/);
  });
});

describe('scrip master mapping', () => {
  it('normalises expiry timestamps to their IST date', () => {
    assert.equal(normalizeExpiry('2026-10-15 14:30:00'), '2026-10-15');
    assert.equal(normalizeExpiry('2026-10-15'), '2026-10-15');
    assert.equal(normalizeExpiry('15-10-2026'), undefined);
  });

  it('maps a complete index option row and drops anything incomplete', () => {
    const contract = toOptionContract(NIFTY_CALL, 'NIFTY', 'NSE_FNO');
    assert.deepEqual(contract, {
      underlying: 'NIFTY',
      securityId: '48001',
      exchangeSegment: 'NSE_FNO',
      symbol: 'NIFTY 15 OCT 22450 CALL',
      optionType: 'CE',
      strike: 22_450,
      expiry: '2026-10-15',
      lotSize: 75,
      tickSize: 0.05,
    });
    assert.equal(toOptionContract({ ...NIFTY_CALL, lotSize: 0 }, 'NIFTY', 'NSE_FNO'), undefined);
    assert.equal(toOptionContract({ ...NIFTY_CALL, tickSize: undefined } as unknown as Instrument, 'NIFTY', 'NSE_FNO'), undefined);
    assert.equal(toOptionContract({ ...NIFTY_CALL, instrument: 'FUTIDX' }, 'NIFTY', 'NSE_FNO'), undefined);
    assert.equal(toOptionContract(NIFTY_CALL, 'BANKNIFTY', 'NSE_FNO'), undefined);
    assert.equal(toOptionContract(NIFTY_CALL, 'NIFTY', 'BSE_FNO'), undefined, 'segment must match exactly');
  });

  it('resolves an index only when exactly one spot instrument matches', async () => {
    const source = {
      bySegment: async () => [
        row({ securityId: '13', symbolName: 'NIFTY', displayName: 'Nifty 50' }),
        row({ securityId: '25', symbolName: 'BANKNIFTY' }),
      ],
    };
    const master = new InstrumentMaster(source, () => '2026-10-12');
    assert.deepEqual(await master.resolveSpot('nifty'), { exchangeSegment: 'IDX_I', securityId: '13' });
    await assert.rejects(master.resolveSpot('FINNIFTY'), /not found/);
  });

  it('refuses an ambiguous index rather than guessing a security id', async () => {
    const source = {
      bySegment: async () => [row({ securityId: '13', symbolName: 'NIFTY' }), row({ securityId: '99', displayName: 'NIFTY' })],
    };
    await assert.rejects(new InstrumentMaster(source, () => '2026-10-12').resolveSpot('NIFTY'), /ambiguous/);
  });

  it('caches contracts for one IST day and fails when a segment has none', async () => {
    let calls = 0;
    let day = '2026-10-12';
    const source = {
      bySegment: async () => {
        calls += 1;
        return [NIFTY_CALL];
      },
    };
    const master = new InstrumentMaster(source, () => day);
    await master.optionContracts('NIFTY', 'NSE_FNO');
    await master.optionContracts('NIFTY', 'NSE_FNO');
    assert.equal(calls, 1);
    day = '2026-10-13';
    await master.optionContracts('NIFTY', 'NSE_FNO');
    assert.equal(calls, 2, 'a new IST day reloads the master');
    const empty = new InstrumentMaster({ bySegment: async () => [] }, () => day);
    await assert.rejects(empty.optionContracts('NIFTY', 'NSE_FNO'), /no NSE_FNO/);
  });
});

describe('market data', () => {
  it('should read the expiry list once per IST day, and not cache an empty answer', async () => {
    let calls = 0;
    let answer: string[] = [];
    const client = { optionChain: { expiryList: async () => ((calls += 1), { data: answer }) } };
    let now = istEpoch('2026-10-13', '09:30');
    const data = new DhanMarketData(client as never, { istShiftedTimestamps: false, now: () => now });
    const spot = { exchangeSegment: 'IDX_I', securityId: '13' };

    assert.deepEqual(await data.listExpiries(spot), []);
    answer = ['2026-10-13', '2026-10-20'];
    assert.deepEqual(await data.listExpiries(spot), answer, 'the empty answer was not kept');
    now = istEpoch('2026-10-13', '14:00');
    await data.listExpiries(spot);
    assert.equal(calls, 2, 'served from the day cache');
    now = istEpoch('2026-10-14', '09:20');
    await data.listExpiries(spot);
    assert.equal(calls, 3, 'read again on the next IST day');
  });

  it('reuses a fresh option chain and throttles to the Dhan rate limit', async () => {
    let now = 1_000_000;
    let calls = 0;
    const client = {
      optionChain: {
        fetchNormalized: async () => {
          calls += 1;
          return { strikes: [{ strike: 22_450, call: { last_price: 100 }, put: undefined }] };
        },
      },
    };
    const data = new DhanMarketData(client as never, { istShiftedTimestamps: false, now: () => now });
    const spot = { exchangeSegment: 'IDX_I', securityId: '13' };
    await data.optionChain(spot, '2026-10-15');
    now += OPTION_CHAIN_MIN_INTERVAL_MS - 1;
    await data.optionChain(spot, '2026-10-15');
    assert.equal(calls, 1);
    now += 2;
    await data.optionChain(spot, '2026-10-15');
    assert.equal(calls, 2);
  });

  it('keeps concurrent chains for different expiries separate and spaces them account-wide', async () => {
    let now = 0;
    const sleeps: number[] = [];
    const requested: string[] = [];
    const client = {
      optionChain: {
        fetchNormalized: async (request: { expiry: string }) => {
          requested.push(request.expiry);
          return { strikes: [{ strike: request.expiry === '2026-10-15' ? 22_450 : 22_500, call: undefined, put: undefined }] };
        },
      },
    };
    const data = new DhanMarketData(client as never, {
      istShiftedTimestamps: false,
      now: () => now,
      sleep: async (ms) => {
        sleeps.push(ms);
        now += ms;
      },
    });
    const spot = { exchangeSegment: 'IDX_I', securityId: '13' };
    const [near, far] = await Promise.all([data.optionChain(spot, '2026-10-15'), data.optionChain(spot, '2026-10-22')]);
    assert.equal(near.strikes[0]?.strike, 22_450);
    assert.equal(far.strikes[0]?.strike, 22_500, 'a second expiry must not receive the first expiry\'s chain');
    assert.deepEqual(requested, ['2026-10-15', '2026-10-22']);
    assert.deepEqual(sleeps, [OPTION_CHAIN_MIN_INTERVAL_MS], 'the second chain call waits out the rate limit');
  });

  it('fails funds reads that carry no usable balance', async () => {
    const data = new DhanMarketData({ funds: { getLimit: async () => ({}) } } as never, { istShiftedTimestamps: false });
    await assert.rejects(data.availableFunds(), /availableBalance/);
  });
});

describe('feed', () => {
  it('accepts only priced ticker, quote and full packets', () => {
    assert.equal(asPriceEvent({ type: 'ticker', exchangeSegment: 'IDX_I', securityId: '13', ltp: 22_450, ltt: 1 })?.ltp, 22_450);
    assert.equal(asPriceEvent({ type: 'oi', exchangeSegment: 'IDX_I', securityId: '13', ltp: 1, ltt: 1 }), undefined);
    assert.equal(asPriceEvent({ type: 'ticker', exchangeSegment: 'IDX_I', securityId: '13', ltp: 0, ltt: 1 }), undefined);
    assert.equal(asPriceEvent(null), undefined);
  });

  function mockFeedClient(listeners: Map<string, (...args: unknown[]) => void>, subscribed: unknown[] = []) {
    return {
      ws: {
        market: {
          on: (event: string, fn: (...args: unknown[]) => void) => listeners.set(event, fn),
          connect: async () => undefined,
          subscribe: (items: unknown[]) => subscribed.push(...items),
          unsubscribe: () => undefined,
        },
        connect: async () => undefined,
        disconnect: () => undefined,
      },
    };
  }

  it('delivers ticks only for subscribed composite keys, with receipt-time freshness', async () => {
    const listeners = new Map<string, (...args: unknown[]) => void>();
    const subscribed: unknown[] = [];
    let now = 5_000;
    const feed = new DhanFeed(mockFeedClient(listeners, subscribed) as never, { istShiftedTimestamps: false, now: () => now });
    const ticks: unknown[] = [];
    feed.onTick((tick) => ticks.push(tick));
    await feed.start();
    feed.subscribe([{ exchangeSegment: 'NSE_FNO', securityId: '48001' }]);
    const handler = listeners.get('tick') as ((value: unknown) => void) | undefined;
    handler?.({ type: 'ticker', exchangeSegment: 'NSE_FNO', securityId: '48001', ltp: 101, ltt: 1_700_000_000 });
    handler?.({ type: 'ticker', exchangeSegment: 'NSE_FNO', securityId: '99999', ltp: 5, ltt: 1_700_000_000 });
    assert.equal(ticks.length, 1);
    assert.deepEqual(subscribed, [{ exchangeSegment: 'NSE_FNO', securityId: '48001' }]);
    assert.equal(feed.ageMs({ exchangeSegment: 'NSE_FNO', securityId: '48001' }, now + 250), 250);
    now += 1;
    feed.unsubscribe([{ exchangeSegment: 'NSE_FNO', securityId: '48001' }]);
    assert.equal(feed.ageMs({ exchangeSegment: 'NSE_FNO', securityId: '48001' }), undefined);
  });

  it('should age a tick by its exchange time when the packet arrives late', async () => {
    const listeners = new Map<string, (...args: unknown[]) => void>();
    const now = 1_700_000_100_000;
    const feed = new DhanFeed(mockFeedClient(listeners) as never, { istShiftedTimestamps: false, now: () => now });
    await feed.start();
    feed.subscribe([{ exchangeSegment: 'IDX_I', securityId: '13' }]);
    (listeners.get('tick') as ((v: unknown) => void) | undefined)?.({
      type: 'ticker', exchangeSegment: 'IDX_I', securityId: '13', ltp: 22_500, ltt: 1_700_000_000,
    });
    assert.equal(feed.ageMs({ exchangeSegment: 'IDX_I', securityId: '13' }), 100_000);
  });

  it('should convert IST-stamped LTT to UTC, and report a tick stamped in the future once', async () => {
    const listeners = new Map<string, (...args: unknown[]) => void>();
    const errors: string[] = [];
    const nowMs = 1_700_000_000_000;
    const logger = { info: () => undefined, warn: () => undefined, error: (message: string) => errors.push(message), debug: () => undefined };
    const ticks: { ltt: number }[] = [];
    const shifted = new DhanFeed(mockFeedClient(listeners) as never, { istShiftedTimestamps: true, now: () => nowMs, logger: logger as never });
    shifted.onTick((tick) => ticks.push(tick));
    await shifted.start();
    shifted.subscribe([{ exchangeSegment: 'IDX_I', securityId: '13' }]);
    (listeners.get('tick') as ((v: unknown) => void) | undefined)?.({
      type: 'ticker', exchangeSegment: 'IDX_I', securityId: '13', ltp: 22_450, ltt: nowMs / 1000 + 19_800,
    });
    assert.equal(ticks[0]?.ltt, nowMs);
    assert.deepEqual(errors, []);

    const unshiftedListeners = new Map<string, (...args: unknown[]) => void>();
    const unshifted = new DhanFeed(mockFeedClient(unshiftedListeners) as never, { istShiftedTimestamps: false, now: () => nowMs, logger: logger as never });
    await unshifted.start();
    unshifted.subscribe([{ exchangeSegment: 'IDX_I', securityId: '13' }]);
    const handler = unshiftedListeners.get('tick') as ((v: unknown) => void) | undefined;
    handler?.({ type: 'ticker', exchangeSegment: 'IDX_I', securityId: '13', ltp: 22_450, ltt: nowMs / 1000 + 19_800 });
    handler?.({ type: 'ticker', exchangeSegment: 'IDX_I', securityId: '13', ltp: 22_451, ltt: nowMs / 1000 + 19_801 });
    assert.equal(errors.length, 1);
    assert.match(errors[0] ?? '', /DHAN_FEED_IST_SHIFTED/);
  });

  it('parses Dhan Response Code 1 index packet from binary buffer', () => {
    const buf = Buffer.alloc(16);
    buf.writeUInt8(1, 0);
    buf.writeInt16LE(16, 1);
    buf.writeUInt8(0, 3);
    buf.writeInt32LE(13, 4);
    buf.writeFloatLE(24500.5, 8);
    buf.writeInt32LE(1700000000, 12);
    const event = parseIndexPacket(buf);
    assert.deepEqual(event, {
      type: 'ticker', exchangeSegment: 'IDX_I', securityId: '13', ltp: Math.fround(24500.5), ltt: 1700000000,
    });
    assert.equal(parseIndexPacket(Buffer.alloc(15)), undefined);
    assert.equal(parseIndexPacket(Buffer.from([2, ...new Array(15).fill(0)])), undefined);
  });

  it('tracks feed lifecycle status and tick count', async () => {
    const listeners = new Map<string, (...args: unknown[]) => void>();
    const feed = new DhanFeed(mockFeedClient(listeners) as never, { istShiftedTimestamps: false });
    assert.equal(feed.status().status, 'disconnected');
    await feed.start();
    assert.equal(feed.status().status, 'connecting');
    listeners.get('open')?.();
    assert.equal(feed.status().status, 'connected');
    listeners.get('close')?.();
    assert.equal(feed.status().status, 'reconnecting');
    listeners.get('disconnect')?.({ reasonCode: 805 });
    assert.equal(feed.status().disconnectReason, 805);
    listeners.get('reconnect_failed')?.();
    assert.equal(feed.status().status, 'disconnected');
  });
});
