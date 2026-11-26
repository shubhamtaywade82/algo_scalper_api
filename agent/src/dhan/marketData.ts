import type { DhanClient } from '@nemesis-oss/dhanhq-sdk';
import type { Candle, InstrumentRef } from '../domain/types.js';
import type { ChainLeg, ChainSnapshot, ChainStrike } from '../options/selector.js';
import { MemoryRateGate, type RateGate } from '../persistence/rateGate.js';
import { dhanEpochSecondsToMs, isMarketSessionOpen, istParts } from '../time/ist.js';

/** Dhan rate-limits `/optionchain` to one call every three seconds. */
export const OPTION_CHAIN_MIN_INTERVAL_MS = 3_000;

const INTRADAY_INTERVALS = { 1: '1', 5: '5', 15: '15', 25: '25', 60: '60' } as const;
export type IntradayInterval = (typeof INTRADAY_INTERVALS)[keyof typeof INTRADAY_INTERVALS];

export function intradayIntervalFor(barMinutes: number): IntradayInterval {
  if (!Object.prototype.hasOwnProperty.call(INTRADAY_INTERVALS, barMinutes)) {
    throw new Error(`BAR_MINUTES must be one of 1, 5, 15, 25, 60 for Dhan intraday charts, got ${barMinutes}`);
  }
  return INTRADAY_INTERVALS[barMinutes as keyof typeof INTRADAY_INTERVALS];
}

/** Column-oriented chart payload to closed bars. Any malformed column fails the whole batch. */
export function mapChartColumns(
  columns: {
    open?: number[];
    high?: number[];
    low?: number[];
    close?: number[];
    volume?: number[];
    timestamp?: number[];
  },
  istShiftedTimestamps: boolean,
): Candle[] {
  const { open, high, low, close, timestamp } = columns;
  if (open === undefined || high === undefined || low === undefined || close === undefined || timestamp === undefined) {
    throw new Error('chart response is missing OHLC or timestamp columns');
  }
  const volume = columns.volume ?? [];
  const length = timestamp.length;
  if ([open, high, low, close].some((column) => column.length !== length)) {
    throw new Error('chart response columns have mismatched lengths');
  }
  const bars = new Map<number, Candle>();
  for (let i = 0; i < length; i += 1) {
    const candle: Candle = {
      time: dhanEpochSecondsToMs(timestamp[i] as number, istShiftedTimestamps),
      open: open[i] as number,
      high: high[i] as number,
      low: low[i] as number,
      close: close[i] as number,
      volume: volume[i] ?? 0,
    };
    const finite = [candle.time, candle.open, candle.high, candle.low, candle.close].every(Number.isFinite);
    if (!finite || candle.high < candle.low || candle.low <= 0) {
      throw new Error(`invalid chart bar at index ${i}`);
    }
    // Dhan can append a zero-volume bar after the close (seen at 18:40 IST on 2026-10-26). Live bars drop
    // post-close ticks, so history drops these too, or warmup indicators see a bar the live series never has.
    if (!isMarketSessionOpen(candle.time)) {
      continue;
    }
    bars.set(candle.time, candle);
  }
  return [...bars.values()].sort((a, b) => a.time - b.time);
}

type MarketDataClient = Pick<DhanClient, 'charts' | 'optionChain' | 'funds'>;

/**
 * REST market data: intraday candles for warmup, expiries, normalised option
 * chains, and available funds.
 *
 * The option-chain endpoint is rate-limited per account, not per instrument, so
 * chain calls are spaced at least OPTION_CHAIN_MIN_INTERVAL_MS apart across every
 * underlying. Snapshots are cached per (segment, security id, expiry), and
 * concurrent callers for the same key share one request.
 */
export class DhanMarketData {
  private readonly chains = new Map<string, { fetchedAt: number; snapshot: ChainSnapshot }>();
  /** Expiries change only between sessions, and the endpoint is option-chain family, so one read per IST day. */
  private readonly expiries = new Map<string, { day: string; list: string[] }>();
  private readonly inFlight = new Map<string, Promise<ChainSnapshot>>();
  private chainTail: Promise<void> = Promise.resolve();
  private readonly gate: RateGate;

  constructor(
    private readonly client: MarketDataClient,
    private readonly options: {
      istShiftedTimestamps: boolean;
      now?: () => number;
      sleep?: (ms: number) => Promise<void>;
      /** Account-wide spacing for chain calls. Redis-backed when two processes share an account. */
      rateGate?: RateGate;
      /** Names the account the rate gate counts against. */
      accountKey?: string;
    },
  ) {
    this.gate =
      options.rateGate ??
      new MemoryRateGate({
        now: options.now ?? Date.now,
        ...(options.sleep === undefined ? {} : { sleep: options.sleep }),
      });
  }

  private get now(): () => number {
    return this.options.now ?? Date.now;
  }

  async intradayCandles(
    spot: InstrumentRef,
    barMinutes: number,
    fromDate: string,
    toDate: string,
  ): Promise<Candle[]> {
    const response = await this.client.charts.intraday({
      securityId: spot.securityId,
      exchangeSegment: 'IDX_I',
      instrument: 'INDEX',
      interval: intradayIntervalFor(barMinutes),
      oi: false,
      fromDate,
      toDate,
    });
    return mapChartColumns(response, this.options.istShiftedTimestamps);
  }

  async listExpiries(spot: InstrumentRef): Promise<string[]> {
    const key = `${spot.exchangeSegment}:${spot.securityId}`;
    const day = istParts(this.now()).date;
    const cached = this.expiries.get(key);
    if (cached !== undefined && cached.day === day) {
      return cached.list;
    }
    const response = await this.client.optionChain.expiryList({
      underlyingScrip: Number(spot.securityId),
      underlyingSeg: spot.exchangeSegment,
    });
    const list = response.data ?? [];
    // An empty answer is not cached: it is more likely a transient gap than a day with no expiries.
    if (list.length > 0) {
      this.expiries.set(key, { day, list });
    }
    return list;
  }

  async optionChain(spot: InstrumentRef, expiry: string): Promise<ChainSnapshot> {
    const key = `${spot.exchangeSegment}:${spot.securityId}:${expiry}`;
    const cached = this.chains.get(key);
    if (cached !== undefined && this.now() - cached.fetchedAt < OPTION_CHAIN_MIN_INTERVAL_MS) {
      return cached.snapshot;
    }
    const pending = this.inFlight.get(key);
    if (pending !== undefined) {
      return pending;
    }
    const request = this.throttledFetch(spot, expiry, key).finally(() => {
      this.inFlight.delete(key);
    });
    this.inFlight.set(key, request);
    return request;
  }

  async availableFunds(): Promise<number> {
    const limit = await this.client.funds.getLimit();
    const balance = limit.availabelBalance;
    if (balance === undefined || !Number.isFinite(balance)) {
      throw new Error('funds response carries no usable availableBalance');
    }
    return balance;
  }

  /** Serialises chain calls account-wide so consecutive requests are never closer than the rate limit. */
  private throttledFetch(spot: InstrumentRef, expiry: string, key: string): Promise<ChainSnapshot> {
    const turn = this.chainTail.then(async () => {
      await this.gate.acquire(this.options.accountKey ?? 'default', OPTION_CHAIN_MIN_INTERVAL_MS);
      return this.fetchChain(spot, expiry, key);
    });
    this.chainTail = turn.then(
      () => undefined,
      () => undefined,
    );
    return turn;
  }

  private async fetchChain(spot: InstrumentRef, expiry: string, key: string): Promise<ChainSnapshot> {
    const normalized = await this.client.optionChain.fetchNormalized({
      underlyingScrip: Number(spot.securityId),
      underlyingSeg: spot.exchangeSegment,
      expiry,
    });
    const fetchedAt = this.now();
    const strikes: ChainStrike[] = normalized.strikes.map((row) => ({
      strike: row.strike,
      call: toLeg(row.call),
      put: toLeg(row.put),
    }));
    const snapshot: ChainSnapshot = { expiry, fetchedAt, strikes };
    this.chains.set(key, { fetchedAt, snapshot });
    return snapshot;
  }
}

function optionalNumber(value: unknown): number | undefined {
  return typeof value === 'number' && Number.isFinite(value) ? value : undefined;
}

function toLeg(leg: Record<string, unknown> | undefined): ChainLeg | undefined {
  if (leg === undefined) {
    return undefined;
  }
  const securityId = leg['security_id'];
  return {
    ltp: optionalNumber(leg['last_price']),
    bid: optionalNumber(leg['top_bid_price']),
    ask: optionalNumber(leg['top_ask_price']),
    oi: optionalNumber(leg['oi']),
    volume: optionalNumber(leg['volume']),
    securityId: securityId === undefined || securityId === null ? undefined : String(securityId),
  };
}
