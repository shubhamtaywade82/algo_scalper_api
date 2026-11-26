import type { Candle, Direction, Signal } from '../domain/types.js';
import { superTrend } from '../market/indicators.js';
import { istParts } from '../time/ist.js';
import { isCompleteSession } from '../time/sessionCoverage.js';
import type { OrbSupertrendParams } from './orbSupertrend.js';

/** The longest ordinary gap between sessions: a Friday to the Monday after it, or a Thursday to the Monday after a Friday holiday. */
const MAX_PREVIOUS_SESSION_GAP_DAYS = 4;
const MS_PER_DAY = 86_400_000;

/**
 * High and low of the latest IST date before `today` in `bars`. Undefined unless that session is complete on the bar
 * grid and no more than four calendar days back. A partial session gives a wrong level: a morning-only high can stand
 * in for the real high, and a breakout is then judged against a line the market never drew.
 */
function previousDayLevels(bars: readonly Candle[], today: string, barMinutes: number): { high: number; low: number } | undefined {
  let day: string | undefined;
  const sessionBars: Candle[] = [];
  for (let i = bars.length - 1; i >= 0; i -= 1) {
    const bar = bars[i];
    const date = bar === undefined ? undefined : istParts(bar.time).date;
    if (bar === undefined || date === undefined || date >= today) {
      continue;
    }
    if (day !== undefined && date !== day) {
      break;
    }
    day = date;
    sessionBars.push(bar);
  }
  if (day === undefined || !isCompleteSession(sessionBars, day, barMinutes)) {
    return undefined;
  }
  const gapDays = (Date.parse(`${today}T00:00:00Z`) - Date.parse(`${day}T00:00:00Z`)) / MS_PER_DAY;
  if (gapDays > MAX_PREVIOUS_SESSION_GAP_DAYS) {
    return undefined;
  }
  return { high: Math.max(...sessionBars.map((bar) => bar.high)), low: Math.min(...sessionBars.map((bar) => bar.low)) };
}

/**
 * A closed bar that crosses the previous session's high (bullish) or low (bearish). Outside scout posture the
 * SuperTrend must agree. Only the crossing bar fires, never a bar already beyond the level.
 */
export function previousDayBreak(bars: readonly Candle[], params: OrbSupertrendParams, isScout: boolean): Signal | undefined {
  const last = bars[bars.length - 1];
  const prev = bars[bars.length - 2];
  if (last === undefined || prev === undefined) return undefined;
  const parts = istParts(last.time);
  if (parts.minuteOfDay < params.entryStartMinute || parts.minuteOfDay >= params.entryEndMinute) return undefined;
  if (istParts(prev.time).date !== parts.date) return undefined;
  const levels = previousDayLevels(bars, parts.date, params.barMinutes);
  if (levels === undefined) return undefined;
  const bullish = last.close > levels.high && prev.close <= levels.high;
  const bearish = last.close < levels.low && prev.close >= levels.low;
  if (!bullish && !bearish) return undefined;
  const direction: Direction = bullish ? 'BULLISH' : 'BEARISH';
  if (!isScout) {
    const trend = superTrend(bars, params.supertrendPeriod, params.supertrendMultiplier);
    if (trend === undefined || trend.trend !== (bullish ? 'UP' : 'DOWN')) return undefined;
  }
  const level = bullish ? levels.high : levels.low;
  return {
    underlying: params.underlying,
    direction,
    barTime: last.time,
    spot: last.close,
    reasons: [`Previous-day break (${bullish ? 'high' : 'low'} ${level} crossed by close ${last.close})`],
  };
}
