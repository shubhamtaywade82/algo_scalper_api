import type { Candle, Direction } from '../domain/types.js';
import { wilderAtr } from '../market/indicators.js';
import type { StructureState } from '../strategy/marketContext.js';

/**
 * Context features a replayed trade can carry without look-ahead (OTA-309). Each takes only what was known at the
 * signal bar. Where the history cannot support a value, the feature is UNKNOWN, never a guessed default.
 */

export type VolatilityBucket = 'LOW' | 'MID' | 'HIGH' | 'UNKNOWN';
export type StructureAlignment = 'WITH' | 'AGAINST' | 'NEUTRAL' | 'UNKNOWN';
export type ExpiryBucket = 'EXPIRY' | 'NEAR' | 'FAR' | 'UNKNOWN';

const ATR_PERIOD = 14;
/** ATR values needed before a percentile means anything. Fewer than this and the bucket is UNKNOWN. */
const MIN_ATR_HISTORY = 30;
const MS_PER_DAY = 86_400_000;
/** Expiries this many sessions away or fewer are NEAR. Beyond that, FAR. */
const NEAR_EXPIRY_DAYS = 2;

/**
 * Where the current ATR sits within the ATR history available at the signal bar: the bottom third is LOW, the top third
 * is HIGH, and the rest is MID. The percentile uses only the bars given, so it cannot see later bars.
 */
export function volatilityBucket(history: readonly Candle[]): VolatilityBucket {
  const atr = wilderAtr(history, ATR_PERIOD).filter((value): value is number => value !== undefined);
  if (atr.length < MIN_ATR_HISTORY) {
    return 'UNKNOWN';
  }
  const current = atr[atr.length - 1];
  if (current === undefined) {
    return 'UNKNOWN';
  }
  const rank = atr.filter((value) => value < current).length / atr.length;
  if (rank < 1 / 3) {
    return 'LOW';
  }
  return rank > 2 / 3 ? 'HIGH' : 'MID';
}

/**
 * The market-structure trend against the trade direction. UNKNOWN until the structure has both a swing high and a swing
 * low, because before that the trend is not a measurement.
 */
export function structureAlignment(structure: StructureState, direction: Direction): StructureAlignment {
  if (structure.lastSwingHigh === undefined || structure.lastSwingLow === undefined) {
    return 'UNKNOWN';
  }
  if (structure.trend === 'NEUTRAL') {
    return 'NEUTRAL';
  }
  return structure.trend === direction ? 'WITH' : 'AGAINST';
}

/**
 * Sessions from the trade day to its expiry. UNKNOWN when the session has no expiry on record (the rolling source does
 * not return one, and BANKNIFTY monthly is not derived), or when the expiry is before the session.
 */
export function expiryBucket(sessionDate: string, expiry: string | undefined): ExpiryBucket {
  if (expiry === undefined) {
    return 'UNKNOWN';
  }
  const days = Math.round((Date.parse(`${expiry}T00:00:00Z`) - Date.parse(`${sessionDate}T00:00:00Z`)) / MS_PER_DAY);
  if (days < 0) {
    return 'UNKNOWN';
  }
  if (days === 0) {
    return 'EXPIRY';
  }
  return days <= NEAR_EXPIRY_DAYS ? 'NEAR' : 'FAR';
}
