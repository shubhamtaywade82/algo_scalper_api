import type { OptionType } from '../domain/types.js';
import { nearestAtmStrike } from '../options/selector.js';
import { istParts } from '../time/ist.js';
import { legBars, sessionStrikes, type ResearchSession } from './dataset.js';

/**
 * Implied-volatility context for entries (research only). Every constant is fixed before any run that uses it. Changing
 * one is a new variant, and the tests pin them so a change cannot pass unnoticed.
 */
/** Prior sessions whose ATM IV forms the history for an entry. */
export const IV_LOOKBACK_SESSIONS = 20;
/** Observations at the same minute of day needed before a percentile means anything. Fewer, and the bucket is UNKNOWN. */
export const IV_MIN_HISTORY = 10;
/** Tercile cut points on the mid-rank percentile of the current IV within its history. */
export const IV_LOW_CUT = 1 / 3;
export const IV_HIGH_CUT = 2 / 3;

export type IvBucket = 'LOW' | 'MID' | 'HIGH' | 'UNKNOWN';

/** One session's ATM IV by minute of day, for each option side. */
export interface IvSessionMaps {
  readonly CE: ReadonlyMap<number, number>;
  readonly PE: ReadonlyMap<number, number>;
}

/** The prior sessions' ATM IV maps for one entry, oldest first. */
export interface IvHistory {
  readonly CE: readonly ReadonlyMap<number, number>[];
  readonly PE: readonly ReadonlyMap<number, number>[];
}

/**
 * The IV of the strike nearest `spot` at bar `time`, for one side. Undefined when that strike has no bar at that time or the
 * bar carries no finite IV. The strike is the one the replay itself uses as ATM, so the feature and the trade agree.
 */
export function atmIvAt(session: ResearchSession, optionType: OptionType, time: number, spot: number): number | undefined {
  const atm = nearestAtmStrike(spot, sessionStrikes(session, optionType));
  if (atm === undefined) {
    return undefined;
  }
  const iv = legBars(session, optionType, atm)?.find((candidate) => candidate.time === time)?.iv;
  return iv !== undefined && Number.isFinite(iv) ? iv : undefined;
}

/** A session's ATM IV at every spot bar that has one, keyed by minute of day. The spot close is the reference, as at a signal. */
export function atmIvByMinute(session: ResearchSession, optionType: OptionType): ReadonlyMap<number, number> {
  const out = new Map<number, number>();
  for (const bar of session.spot) {
    const iv = atmIvAt(session, optionType, bar.time, bar.close);
    if (iv !== undefined) {
      out.set(istParts(bar.time).minuteOfDay, iv);
    }
  }
  return out;
}

/** The up-to-LOOKBACK sessions before `index`. The entry's own session and every later one are excluded. */
export function trailingIvHistory(perSession: readonly IvSessionMaps[], index: number): IvHistory {
  const prior = perSession.slice(Math.max(0, index - IV_LOOKBACK_SESSIONS), index);
  return { CE: prior.map((session) => session.CE), PE: prior.map((session) => session.PE) };
}

/**
 * The bucket of `iv` within the history at `minute`. The percentile is the mid-rank share of history strictly below `iv`,
 * with ties at half weight, so a tie does not push the bucket either way.
 */
export function ivBucketFor(history: readonly ReadonlyMap<number, number>[], minute: number, iv: number | undefined): IvBucket {
  if (iv === undefined || !Number.isFinite(iv)) {
    return 'UNKNOWN';
  }
  const current: number = iv;
  const values: number[] = [];
  for (const session of history) {
    const value = session.get(minute);
    if (value !== undefined) {
      values.push(value);
    }
  }
  if (values.length < IV_MIN_HISTORY) {
    return 'UNKNOWN';
  }
  const below = values.filter((value) => value < current).length;
  const tied = values.filter((value) => value === current).length;
  const rank = (below + tied / 2) / values.length;
  if (rank < IV_LOW_CUT) {
    return 'LOW';
  }
  return rank >= IV_HIGH_CUT ? 'HIGH' : 'MID';
}
