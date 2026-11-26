import type { Candle } from '../domain/types.js';
import { istParts, NSE_SESSION_CLOSE_MINUTE, NSE_SESSION_OPEN_MINUTE } from './ist.js';

/**
 * Bars a window holds on the bar grid, for `[fromMinute, toMinute)` and bars `barMinutes` long. Shared by the opening
 * range and by full-session checks, so both count bars the same way.
 */
export function barsInWindow(fromMinute: number, toMinute: number, barMinutes: number): number {
  return Math.ceil((toMinute - fromMinute) / barMinutes);
}

/**
 * True when `bars` cover the whole NSE session of `date` on the bar grid: every expected bar, in order, with no gap and
 * no extra bar. A session that is short or misaligned gives no reliable high or low, so it is not complete.
 */
export function isCompleteSession(bars: readonly Candle[], date: string, barMinutes: number): boolean {
  const expected = barsInWindow(NSE_SESSION_OPEN_MINUTE, NSE_SESSION_CLOSE_MINUTE, barMinutes);
  if (bars.length !== expected) {
    return false;
  }
  const ordered = [...bars].sort((a, b) => a.time - b.time);
  return ordered.every((bar, index) => {
    const parts = istParts(bar.time);
    return parts.date === date && parts.minuteOfDay === NSE_SESSION_OPEN_MINUTE + index * barMinutes;
  });
}
