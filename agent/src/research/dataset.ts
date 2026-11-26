import { z } from 'zod';
import type { Candle, OptionSegment, OptionType } from '../domain/types.js';
import { minStrikeStep } from '../options/selector.js';
import { dhanEpochSecondsToMs, istParts, NSE_SESSION_CLOSE_MINUTE, NSE_SESSION_OPEN_MINUTE } from '../time/ist.js';

/**
 * One IST trading day of research data: the index's own bars, and premium bars for each strike keyed by the
 * real strike, never by an ATM offset. A replay can only price a held contract from its own series.
 */
export interface ResearchSession {
  /** `YYYY-MM-DD`, IST. */
  readonly date: string;
  /** Lot size in force on this date. Exchange lot sizes change, so it is stored per day, never looked up today. */
  readonly lotSize: number;
  readonly tickSize: number;
  readonly strikeStep: number;
  /** Expiry of the series, when the source records it. The rolling-option source does not. */
  readonly expiry?: string | undefined;
  readonly spot: readonly Candle[];
  /** Strike (as a decimal string) to that strike's bars, ascending by time. */
  readonly calls: Readonly<Record<string, readonly OptionBar[]>>;
  readonly puts: Readonly<Record<string, readonly OptionBar[]>>;
}

/**
 * Which fetcher, parser and response layout produced a dataset (OTA-311 provenance decision). The parser and layout
 * versions are bumped whenever either changes, so a dataset cannot be silently reinterpreted by a newer parser.
 */
export const ROLLING_PARSER_VERSION = 'rollingoption-v1';
export const ROLLING_RESPONSE_SCHEMA_VERSION = 'rollingoption-layout-1';

export interface DatasetProvenance {
  /** The exact installed broker SDK version that performed the fetch. */
  readonly sdkVersion: string;
  readonly parserVersion: string;
  readonly responseSchemaVersion: string;
}

export interface ResearchDataset {
  readonly version: 1;
  readonly underlying: string;
  readonly optionSegment: OptionSegment;
  readonly barMinutes: number;
  readonly source: {
    readonly kind: 'dhan_rollingoption' | 'fixture';
    readonly expiryFlag?: string | undefined;
    readonly expiryCode?: number | undefined;
    /** ATM ± this many strikes were fetched; a held strike that drifts further has no series. */
    readonly offsets?: number | undefined;
    readonly fetchedAt?: string | undefined;
    /** Same (strike, bar) seen from two ATM offsets with different OHLC. */
    readonly conflictingBars?: number | undefined;
    /** Absent on datasets fetched before provenance was recorded. Those are not comparable to new ones without a re-fetch. */
    readonly provenance?: DatasetProvenance | undefined;
  };
  readonly sessions: readonly ResearchSession[];
}

const candleSchema = z.object({
  time: z.number().int(),
  open: z.number().positive(),
  high: z.number().positive(),
  low: z.number().positive(),
  close: z.number().positive(),
  volume: z.number().nonnegative(),
});

/** Datasets fetched before IV/OI were requested carry neither field. */
const optionBarSchema = candleSchema.extend({
  iv: z.number().nonnegative().optional(),
  oi: z.number().nonnegative().optional(),
});

const sessionSchema = z.object({
  date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
  lotSize: z.number().int().positive(),
  tickSize: z.number().positive(),
  strikeStep: z.number().positive(),
  expiry: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
  spot: z.array(candleSchema),
  calls: z.record(z.string(), z.array(optionBarSchema)),
  puts: z.record(z.string(), z.array(optionBarSchema)),
});

const datasetSchema = z.object({
  version: z.literal(1),
  underlying: z.string().min(1),
  optionSegment: z.enum(['NSE_FNO', 'BSE_FNO']),
  barMinutes: z.number().int().positive(),
  source: z.object({
    kind: z.enum(['dhan_rollingoption', 'fixture']),
    expiryFlag: z.string().optional(),
    expiryCode: z.number().int().optional(),
    offsets: z.number().int().nonnegative().optional(),
    fetchedAt: z.string().optional(),
    conflictingBars: z.number().int().nonnegative().optional(),
    provenance: z
      .object({ sdkVersion: z.string().min(1), parserVersion: z.string().min(1), responseSchemaVersion: z.string().min(1) })
      .optional(),
  }),
  sessions: z.array(sessionSchema),
});

function assertBars(bars: readonly Candle[], date: string, label: string, barMs: number): void {
  let previous: number | undefined;
  for (const bar of bars) {
    const parts = istParts(bar.time);
    if (parts.date !== date) {
      throw new Error(`${label}: bar at ${bar.time} is on ${parts.date}, not ${date}`);
    }
    if (parts.minuteOfDay < NSE_SESSION_OPEN_MINUTE || parts.minuteOfDay >= NSE_SESSION_CLOSE_MINUTE) {
      throw new Error(`${label}: bar at IST minute ${parts.minuteOfDay} is outside the session (check the epoch convention)`);
    }
    if (bar.time % 60_000 !== 0 || ((parts.minuteOfDay - NSE_SESSION_OPEN_MINUTE) * 60_000) % barMs !== 0) {
      throw new Error(`${label}: bar at ${bar.time} is off the ${barMs / 60_000}-minute grid`);
    }
    if (bar.high < bar.low || bar.open > bar.high || bar.open < bar.low || bar.close > bar.high || bar.close < bar.low) {
      throw new Error(`${label}: bar at ${bar.time} has inconsistent OHLC`);
    }
    if (previous !== undefined && bar.time <= previous) {
      throw new Error(`${label}: bars are not strictly ascending at ${bar.time}`);
    }
    previous = bar.time;
  }
}

/**
 * Parses and checks a dataset. Anything the replay would otherwise have to guess about (unsorted bars, bars
 * outside the session, OHLC that cannot exist, duplicate days) refuses the whole file.
 */
export function parseDataset(raw: unknown): ResearchDataset {
  const parsed = datasetSchema.safeParse(raw);
  if (!parsed.success) {
    throw new Error(`invalid research dataset: ${parsed.error.issues.map((issue) => `${issue.path.join('.')}: ${issue.message}`).join('; ')}`);
  }
  const dataset = parsed.data as ResearchDataset;
  const barMs = dataset.barMinutes * 60_000;
  let previousDate = '';
  for (const session of dataset.sessions) {
    if (session.date <= previousDate) {
      throw new Error(`sessions must be strictly ascending by date: ${session.date} follows ${previousDate}`);
    }
    previousDate = session.date;
    assertBars(session.spot, session.date, `${session.date} spot`, barMs);
    for (const [side, legs] of [['CE', session.calls], ['PE', session.puts]] as const) {
      for (const [strike, bars] of Object.entries(legs)) {
        if (!Number.isFinite(Number(strike))) {
          throw new Error(`${session.date} ${side}: strike key "${strike}" is not a number`);
        }
        assertBars(bars, session.date, `${session.date} ${side} ${strike}`, barMs);
      }
    }
  }
  return dataset;
}

export function legBars(session: ResearchSession, optionType: OptionType, strike: number): readonly OptionBar[] | undefined {
  return (optionType === 'CE' ? session.calls : session.puts)[strikeKey(strike)];
}

export function strikeKey(strike: number): string {
  return String(Number(strike.toFixed(2)));
}

export function sessionStrikes(session: ResearchSession, optionType: OptionType): number[] {
  return Object.keys(optionType === 'CE' ? session.calls : session.puts)
    .map(Number)
    .sort((a, b) => a - b);
}

/** A premium bar with the source's implied volatility (annualised %) and open interest, when fetched. */
export interface OptionBar extends Candle {
  readonly iv?: number | undefined;
  readonly oi?: number | undefined;
}

/** One bar of a rolling (ATM-relative) option series, tagged with the real strike it priced at that bar. */
export interface RollingBar extends OptionBar {
  readonly strike: number;
}

function numberColumn(columns: Record<string, unknown>, name: string, length: number | undefined): number[] {
  const column = columns[name];
  if (!Array.isArray(column) || (length !== undefined && column.length !== length)) {
    throw new Error(`rolling option response: column "${name}" is missing or has the wrong length`);
  }
  return column.map((value, index) => {
    if (typeof value !== 'number' || !Number.isFinite(value)) {
      throw new Error(`rolling option response: "${name}"[${index}] is not a finite number`);
    }
    return value;
  });
}

/**
 * Reads one `/charts/rollingoption` response. The SDK passes the body through untyped, so this accepts only the
 * column layout `{ data: { ce | pe: { open, high, low, close, strike, timestamp, volume? } } }` and refuses
 * anything else with the keys it did find. Run `npm run timemachine -- fetch --dump-raw` against a live account
 * once to confirm the layout before trusting a dataset.
 */
export function parseRollingOptionResponse(raw: unknown, optionType: OptionType, istShiftedTimestamps: boolean): RollingBar[] {
  const data = (raw as { data?: unknown } | null)?.data;
  const sideKey = optionType === 'CE' ? 'ce' : 'pe';
  const columns = (data as Record<string, unknown> | null | undefined)?.[sideKey];
  if (columns === null || columns === undefined) {
    const keys = data !== null && typeof data === 'object' ? Object.keys(data).join(',') : typeof data;
    if (data !== null && typeof data === 'object' && sideKey in data) {
      return [];
    }
    throw new Error(`rolling option response has no data.${sideKey} (found: ${keys})`);
  }
  if (typeof columns !== 'object') {
    throw new Error(`rolling option response: data.${sideKey} is not an object`);
  }
  const record = columns as Record<string, unknown>;
  const timestamp = numberColumn(record, 'timestamp', undefined);
  const length = timestamp.length;
  const open = numberColumn(record, 'open', length);
  const high = numberColumn(record, 'high', length);
  const low = numberColumn(record, 'low', length);
  const close = numberColumn(record, 'close', length);
  const strike = numberColumn(record, 'strike', length);
  const volume = Array.isArray(record['volume']) ? numberColumn(record, 'volume', length) : [];
  const iv = Array.isArray(record['iv']) ? numberColumn(record, 'iv', length) : [];
  const oi = Array.isArray(record['oi']) ? numberColumn(record, 'oi', length) : [];
  const bars: RollingBar[] = [];
  for (let i = 0; i < length; i += 1) {
    const bar: RollingBar = {
      time: dhanEpochSecondsToMs(timestamp[i] as number, istShiftedTimestamps),
      open: open[i] as number,
      high: high[i] as number,
      low: low[i] as number,
      close: close[i] as number,
      volume: volume[i] ?? 0,
      strike: strike[i] as number,
      ...(iv[i] === undefined ? {} : { iv: iv[i] }),
      ...(oi[i] === undefined ? {} : { oi: oi[i] }),
    };
    // A zero or negative premium is not a trade print; it is a gap in the source. Skip the bar rather than
    // price a fill off it. Inconsistent OHLC on a positive print means the parse is wrong, so that refuses.
    if (bar.low <= 0 || bar.strike <= 0) {
      continue;
    }
    if (bar.high < bar.low || bar.open > bar.high || bar.open < bar.low || bar.close > bar.high || bar.close < bar.low) {
      throw new Error(`rolling option response: bar ${i} has inconsistent OHLC`);
    }
    bars.push(bar);
  }
  return bars;
}

/**
 * Re-keys several ATM-offset series by the strike each bar actually priced. A strike that was ATM+1 at 10:00 and
 * ATM at 11:00 becomes one continuous series. When two offsets report the same (strike, bar) the first is kept
 * and the disagreement counted, so a dataset with many conflicts can be refused by the caller.
 */
export function pivotByStrike(series: readonly (readonly RollingBar[])[]): { byStrike: Map<number, OptionBar[]>; conflicts: number } {
  const cells = new Map<number, Map<number, OptionBar>>();
  let conflicts = 0;
  for (const bars of series) {
    for (const bar of bars) {
      const strike = Number(bar.strike.toFixed(2));
      let byTime = cells.get(strike);
      if (byTime === undefined) {
        byTime = new Map();
        cells.set(strike, byTime);
      }
      const existing = byTime.get(bar.time);
      const { strike: _strike, ...candle } = bar;
      if (existing === undefined) {
        byTime.set(bar.time, candle);
      } else if (existing.open !== candle.open || existing.high !== candle.high || existing.low !== candle.low || existing.close !== candle.close) {
        conflicts += 1;
      }
    }
  }
  const byStrike = new Map<number, OptionBar[]>();
  for (const [strike, byTime] of cells) {
    byStrike.set(strike, [...byTime.values()].sort((a, b) => a.time - b.time));
  }
  return { byStrike, conflicts };
}

/** Splits spot and per-strike premium bars into IST sessions. Days without spot bars are dropped. */
export function buildSessions(input: {
  spot: readonly Candle[];
  calls: ReadonlyMap<number, readonly OptionBar[]>;
  puts: ReadonlyMap<number, readonly OptionBar[]>;
  lotSize: number;
  tickSize: number;
  fromDate: string;
  toDate: string;
}): ResearchSession[] {
  const byDate = new Map<string, { spot: Candle[]; calls: Record<string, OptionBar[]>; puts: Record<string, OptionBar[]> }>();
  const day = (date: string): { spot: Candle[]; calls: Record<string, OptionBar[]>; puts: Record<string, OptionBar[]> } => {
    let entry = byDate.get(date);
    if (entry === undefined) {
      entry = { spot: [], calls: {}, puts: {} };
      byDate.set(date, entry);
    }
    return entry;
  };
  const inRange = (date: string): boolean => date >= input.fromDate && date <= input.toDate;
  for (const bar of input.spot) {
    const parts = istParts(bar.time);
    if (inRange(parts.date) && parts.minuteOfDay >= NSE_SESSION_OPEN_MINUTE && parts.minuteOfDay < NSE_SESSION_CLOSE_MINUTE) {
      day(parts.date).spot.push(bar);
    }
  }
  for (const [legs, side] of [[input.calls, 'calls'], [input.puts, 'puts']] as const) {
    for (const [strike, bars] of legs) {
      for (const bar of bars) {
        const parts = istParts(bar.time);
        const entry = byDate.get(parts.date);
        if (entry === undefined || parts.minuteOfDay < NSE_SESSION_OPEN_MINUTE || parts.minuteOfDay >= NSE_SESSION_CLOSE_MINUTE) {
          continue;
        }
        (entry[side][strikeKey(strike)] ??= []).push(bar);
      }
    }
  }
  const sessions: ResearchSession[] = [];
  for (const [date, entry] of [...byDate.entries()].sort(([a], [b]) => a.localeCompare(b))) {
    if (entry.spot.length === 0) {
      continue;
    }
    const strikes = [...new Set([...Object.keys(entry.calls), ...Object.keys(entry.puts)].map(Number))].sort((a, b) => a - b);
    const strikeStep = minStrikeStep(strikes);
    if (strikeStep === undefined) {
      continue;
    }
    sessions.push({
      date,
      lotSize: input.lotSize,
      tickSize: input.tickSize,
      strikeStep,
      spot: entry.spot.sort((a, b) => a.time - b.time),
      calls: entry.calls,
      puts: entry.puts,
    });
  }
  return sessions;
}
