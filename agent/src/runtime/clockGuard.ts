import type { Candle } from '../domain/types.js';
import { istParts, NSE_SESSION_CLOSE_MINUTE, NSE_SESSION_OPEN_MINUTE } from '../time/ist.js';

/** Allowance for clock skew between this host and the exchange-stamped bars. */
const FUTURE_TOLERANCE_MS = 60_000;

/**
 * Startup check that the epoch convention (DHAN_EPOCH_IST_SHIFTED) matches the
 * data. A wrong value shifts every bar by 5h30m, which silently moves ORB and
 * session checks off the real clock, so startup refuses instead.
 *
 * - Newest bar ahead of the wall clock: the convention is wrong (shifted up).
 * - On a session day, newest bar of today far behind the clock: wrong convention (shifted down) or a dead feed.
 *
 * With no bars the check passes; the strategy simply produces no signal.
 */
export function assertWarmupClock(newest: Candle | undefined, nowMs: number, barMinutes: number): void {
  if (newest === undefined) {
    return;
  }
  const barMs = barMinutes * 60_000;
  if (newest.time > nowMs + FUTURE_TOLERANCE_MS) {
    throw new Error(
      `newest warmup bar ${new Date(newest.time).toISOString()} is ahead of the wall clock; check DHAN_EPOCH_IST_SHIFTED`,
    );
  }
  const now = istParts(nowMs);
  const barDate = istParts(newest.time).date;
  const inSession =
    now.minuteOfDay >= NSE_SESSION_OPEN_MINUTE + barMinutes && now.minuteOfDay < NSE_SESSION_CLOSE_MINUTE;
  if (inSession && barDate === now.date && nowMs - newest.time > 3 * barMs) {
    throw new Error(
      `newest warmup bar ${new Date(newest.time).toISOString()} is more than three bars behind the wall clock during the session; check DHAN_EPOCH_IST_SHIFTED or the feed`,
    );
  }
}
