import { strict as assert } from 'node:assert';
import { describe, it } from 'node:test';
import type { Candle } from '../src/domain/types.js';
import type { OrbSupertrendParams } from '../src/strategy/orbSupertrend.js';
import { previousDayBreak } from '../src/strategy/levelBreak.js';
import { bar, istEpoch } from './support/fixtures.js';

/** OTA-310. A previous-day level comes only from a complete session, or the breakout is judged against a wrong line. */

const PREV = '2026-10-09'; // a Friday
const TODAY = '2026-10-12'; // the following Monday: a three-day gap
const PARAMS: OrbSupertrendParams = {
  underlying: 'NIFTY',
  orbMinutes: 15,
  barMinutes: 5,
  supertrendPeriod: 10,
  supertrendMultiplier: 3,
  emaFast: 9,
  emaSlow: 21,
  entryStartMinute: 9 * 60 + 30,
  entryEndMinute: 14 * 60 + 30,
  sessionOpenMinute: 9 * 60 + 15,
};

const OPEN = 9 * 60 + 15;
const CLOSE = 15 * 60 + 30;
const clock = (minute: number): string => `${String(Math.floor(minute / 60)).padStart(2, '0')}:${String(minute % 60).padStart(2, '0')}`;

/**
 * A full session on `date` with its true high of 25,260 at 13:00 and a morning-only high of 25,180 at 10:00. `count` keeps
 * only the first bars, which models a truncated session. `skip` removes the first bars, which models missing opening bars.
 */
function session(date: string, barMinutes: number, options: { count?: number; skip?: number } = {}): Candle[] {
  const total = (CLOSE - OPEN) / barMinutes;
  const minutes = Array.from({ length: options.count ?? total }, (_, i) => OPEN + ((options.skip ?? 0) + i) * barMinutes);
  return minutes.map((minute) => {
    const high = minute === 13 * 60 ? 25_260 : minute === 10 * 60 ? 25_180 : 25_100.5;
    return bar(istEpoch(date, clock(minute)), 25_100, high, 25_099.5, 25_100);
  });
}

/** The day's bars up to a close above the previous high, which is the bar that would signal. */
function today(barMinutes: number): Candle[] {
  const minutes: number[] = [];
  for (let minute = OPEN + 30; minute <= 10 * 60 + 5; minute += barMinutes) {
    minutes.push(minute);
  }
  return minutes.map((minute, i) => {
    const close = i === minutes.length - 1 ? 25_270 : 25_100;
    return bar(istEpoch(TODAY, clock(minute)), 25_100, close + 0.5, 25_099.5, close);
  });
}

const signalOn = (bars: Candle[], params: OrbSupertrendParams = PARAMS): ReturnType<typeof previousDayBreak> =>
  previousDayBreak(bars, params, true);

describe('previous-day breakout levels (OTA-310)', () => {
  it('uses the true high of a complete previous session', () => {
    const signal = signalOn([...session(PREV, 5), ...today(5)]);
    assert.equal(signal?.direction, 'BULLISH');
    assert.match(signal?.reasons[0] ?? '', /high 25260/);
  });

  it('refuses a morning-only previous session rather than using its 25,180 high, which the afternoon exceeded', () => {
    // The audit's case. With the afternoon missing, 25,180 would be taken as the level, and 25,270 would look like a break.
    const morningOnly = session(PREV, 5, { count: (11 * 60 + 30 - OPEN) / 5 });
    assert.equal(signalOn([...morningOnly, ...today(5)]), undefined);
  });

  it('refuses a previous session that is missing its closing bars', () => {
    assert.equal(signalOn([...session(PREV, 5, { count: (14 * 60 + 30 - OPEN) / 5 }), ...today(5)]), undefined);
  });

  it('refuses a previous session that is missing its opening bars', () => {
    assert.equal(signalOn([...session(PREV, 5, { skip: 3 }), ...today(5)]), undefined);
  });

  it('refuses a short session, such as the 63-bar Muhurat session in the NIFTY 2025H data', () => {
    assert.equal(signalOn([...session(PREV, 5, { count: 63 }), ...today(5)]), undefined);
  });

  it('accepts a previous session four calendar days back, which covers an ordinary long weekend', () => {
    const thursday = '2026-10-08';
    assert.equal(signalOn([...session(thursday, 5), ...today(5)])?.direction, 'BULLISH');
  });

  it('refuses a previous session more than four calendar days back, because the day between is not in the history', () => {
    const wednesday = '2026-10-07';
    assert.equal(signalOn([...session(wednesday, 5), ...today(5)]), undefined);
  });

  it('refuses when the warmup history holds no previous session at all', () => {
    assert.equal(signalOn(today(5)), undefined);
  });

  it('works at one-minute bars, and refuses five-minute data labelled as one-minute', () => {
    const oneMinute = { ...PARAMS, barMinutes: 1 };
    assert.equal(signalOn([...session(PREV, 1), ...today(1)], oneMinute)?.direction, 'BULLISH');
    assert.equal(signalOn([...session(PREV, 5), ...today(1)], oneMinute), undefined);
  });
});
