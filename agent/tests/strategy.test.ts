import { strict as assert } from 'node:assert';
import { describe, it } from 'node:test';
import type { Candle } from '../src/domain/types.js';
import { evaluateOrbSupertrend, type OrbSupertrendParams } from '../src/strategy/orbSupertrend.js';
import { superTrend } from '../src/market/indicators.js';
import { StrategySession } from '../src/strategy/session.js';
import { previousDayBreak } from '../src/strategy/levelBreak.js';
import { bar, istEpoch, SESSION_DAY } from './support/fixtures.js';

const PREVIOUS_DAY = '2026-10-09';

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

function hhmm(minute: number): string {
  return `${String(Math.floor(minute / 60)).padStart(2, '0')}:${String(minute % 60).padStart(2, '0')}`;
}

/** Five-minute bars on one IST date, each with a symmetric ±0.5 range around `close`. */
function dayBars(dateKey: string, fromMinute: number, closes: readonly number[]): Candle[] {
  return closes.map((close, index) =>
    bar(istEpoch(dateKey, hhmm(fromMinute + index * 5)), close, close + 0.5, close - 0.5, close),
  );
}

/** Previous session rising 90 → 100 so SuperTrend is established UP before today opens. */
function risingWarmup(): Candle[] {
  const closes = Array.from({ length: 60 }, (_, i) => 90 + (i * 10) / 59);
  return dayBars(PREVIOUS_DAY, 9 * 60 + 15, closes);
}

/** Today's opening range (09:15-09:25 bars) sits around 100 with its high at 100.5. */
const ORB_CLOSES = [100, 100, 100];

describe('evaluateOrbSupertrend', () => {
  it('fires BULLISH on the bar that closes through the ORB high in an established uptrend', () => {
    const today = dayBars(SESSION_DAY, 9 * 60 + 15, [...ORB_CLOSES, 100.1, 100.2, 100.3, 101.5]);
    const bars = [...risingWarmup(), ...today];
    const signal = evaluateOrbSupertrend(bars, PARAMS);
    assert.equal(signal?.direction, 'BULLISH');
    assert.equal(signal?.spot, 101.5);
    assert.equal(signal?.barTime, today[today.length - 1]?.time);
  });

  it('does not re-fire when the previous bar already closed beyond the ORB level', () => {
    const today = dayBars(SESSION_DAY, 9 * 60 + 15, [...ORB_CLOSES, 100.1, 101.5, 101.8]);
    assert.equal(evaluateOrbSupertrend([...risingWarmup(), ...today], PARAMS), undefined);
  });

  it('requires SuperTrend confirmation: a level break against a downtrend is not a signal', () => {
    const falling = Array.from({ length: 60 }, (_, i) => 110 - (i * 10) / 59);
    const warmup = dayBars(PREVIOUS_DAY, 9 * 60 + 15, falling);
    const today = dayBars(SESSION_DAY, 9 * 60 + 15, [...ORB_CLOSES, 100.1, 100.2, 100.3, 101.5]);
    assert.equal(evaluateOrbSupertrend([...warmup, ...today], PARAMS), undefined);
  });

  it('produces no signal while the opening range is still forming', () => {
    const today = dayBars(SESSION_DAY, 9 * 60 + 15, [100, 100, 101.5]);
    assert.equal(evaluateOrbSupertrend([...risingWarmup(), ...today], PARAMS), undefined);
  });

  it('produces no signal when an opening-range bar is missing', () => {
    const today = dayBars(SESSION_DAY, 9 * 60 + 15, [...ORB_CLOSES, 100.1, 100.2, 100.3, 101.5]);
    const withGap = today.filter((_, index) => index !== 1);
    assert.equal(evaluateOrbSupertrend([...risingWarmup(), ...withGap], PARAMS), undefined, 'a range from two of three bars is not the opening range');
  });

  it('produces no signal outside the entry window', () => {
    const today = dayBars(SESSION_DAY, 9 * 60 + 15, [...ORB_CLOSES, ...Array.from({ length: 64 }, () => 100.3), 101.5]);
    assert.equal(evaluateOrbSupertrend([...risingWarmup(), ...today], PARAMS), undefined);
  });

  it('never lets another IST session widen today\'s opening range', () => {
    const outlier = bar(istEpoch(PREVIOUS_DAY, '09:20'), 100, 103, 99.5, 100);
    const today = dayBars(SESSION_DAY, 9 * 60 + 15, [...ORB_CLOSES, 100.1, 100.2, 100.3, 101.5]);
    const signal = evaluateOrbSupertrend([...risingWarmup(), outlier, ...today], PARAMS);
    assert.equal(signal?.direction, 'BULLISH', 'a previous-day high of 103 must not raise today\'s ORB above 101.5');
  });
});

describe('StrategySession', () => {
  it('cycles posture across scout, aligned and confirmed', () => {
    const session = new StrategySession('aligned');
    assert.equal(session.view().posture, 'aligned');
    assert.match(session.cyclePosture(), /confirmed/);
    assert.equal(session.view().posture, 'confirmed');
    assert.match(session.cyclePosture(), /scout/);
    assert.equal(session.view().posture, 'scout');
    assert.match(session.cyclePosture(), /aligned/);
    assert.equal(session.view().posture, 'aligned');
  });

  it('toggles strategies and reports state', () => {
    const session = new StrategySession();
    assert.equal(session.view().strategies.find((s) => s.id === 'range')?.on, true);
    assert.match(session.toggle('range'), /Range break off/);
    assert.equal(session.view().strategies.find((s) => s.id === 'range')?.on, false);
    assert.match(session.toggle('range'), /Range break on/);
    assert.equal(session.view().strategies.find((s) => s.id === 'range')?.on, true);
  });

  it('returns undefined when all strategies are disabled', () => {
    const session = new StrategySession('aligned');
    for (const strat of session.view().strategies) {
      if (strat.on) session.toggle(strat.id);
    }
    const today = dayBars(SESSION_DAY, 9 * 60 + 15, [...ORB_CLOSES, 100.1, 100.2, 100.3, 101.5]);
    const bars = [...risingWarmup(), ...today];
    assert.equal(session.evaluate(bars, PARAMS), undefined);
  });

  it('in scout posture, fires on raw level break without requiring trend confirmation', () => {
    const session = new StrategySession('scout');
    const falling = Array.from({ length: 60 }, (_, i) => 110 - (i * 10) / 59);
    const warmup = dayBars(PREVIOUS_DAY, 9 * 60 + 15, falling);
    const today = dayBars(SESSION_DAY, 9 * 60 + 15, [...ORB_CLOSES, 100.1, 100.2, 100.3, 101.5]);
    const signal = session.evaluate([...warmup, ...today], PARAMS);
    assert.ok(signal !== undefined, 'scout fires aggressively without SuperTrend confluence');
    assert.equal(signal?.direction, 'BULLISH');
    assert.match(signal?.reasons[0] ?? '', /Range break/);
  });

  it('in aligned posture, requires SuperTrend and EMA confluence', () => {
    const session = new StrategySession('aligned');
    const falling = Array.from({ length: 60 }, (_, i) => 110 - (i * 10) / 59);
    const warmup = dayBars(PREVIOUS_DAY, 9 * 60 + 15, falling);
    const today = dayBars(SESSION_DAY, 9 * 60 + 15, [...ORB_CLOSES, 100.1, 100.2, 100.3, 101.5]);
    assert.equal(session.evaluate([...warmup, ...today], PARAMS), undefined);

    const risingToday = dayBars(SESSION_DAY, 9 * 60 + 15, [...ORB_CLOSES, 100.1, 100.2, 100.3, 101.5]);
    const signal = session.evaluate([...risingWarmup(), ...risingToday], PARAMS);
    assert.ok(signal !== undefined);
    assert.equal(signal?.direction, 'BULLISH');
  });

  it('in confirmed posture, requires prior bar break and current bar hold beyond the range', () => {
    const session = new StrategySession('confirmed');
    // Today: break happens on 101.5, next bar closes at 101.8 holding beyond range
    const today = dayBars(SESSION_DAY, 9 * 60 + 15, [...ORB_CLOSES, 100.1, 100.2, 100.3, 101.5, 101.8]);
    const signal = session.evaluate([...risingWarmup(), ...today], PARAMS);
    assert.ok(signal !== undefined, 'confirmed fires after breakout holds');
    assert.equal(signal?.direction, 'BULLISH');
    assert.match(signal?.reasons[0] ?? '', /Range break/);
    assert.match(signal?.reasons[0] ?? '', /held beyond the range/);
  });

  it('in scout posture with only trend enabled, fires on adaptive SuperTrend flip', () => {
    const session = new StrategySession('scout', ['trend']);
    assert.deepEqual(session.view().strategies.map((s) => ({ id: s.id, on: s.on })), [
      { id: 'range', on: false },
      { id: 'trend', on: true },
      { id: 'ema_cross', on: false },
      { id: 'momentum', on: false },
      { id: 'continuation', on: false },
      { id: 'prev_day', on: false },
    ]);

    const fallingWarmup = dayBars(PREVIOUS_DAY, 9 * 60 + 15, Array.from({ length: 60 }, (_, i) => 120 - (i * 20) / 59));
    const today = dayBars(SESSION_DAY, 9 * 60 + 15, [100, 100, 100, 100.5, 108]);
    const signal = session.evaluate([...fallingWarmup, ...today], PARAMS);
    assert.ok(signal !== undefined, 'adaptive SuperTrend flip should fire');
    assert.equal(signal?.strategy, 'trend');
    assert.match(signal?.reasons[0] ?? '', /adaptive flip/);
    assert.match(signal?.reasons[0] ?? '', /exact flip/);
    assert.ok(signal?.flipBarTime !== undefined);
  });

  it('in scout posture, allows entry within maxBarsSinceFlip candles of the flip', () => {
    const session = new StrategySession('scout', ['trend']);
    const fallingWarmup = dayBars(PREVIOUS_DAY, 9 * 60 + 15, Array.from({ length: 60 }, (_, i) => 120 - (i * 20) / 59));
    // Flip happened on bar at 108. Next 2 bars continue up: 109, 110. (barsSinceFlip = 2)
    const today = dayBars(SESSION_DAY, 9 * 60 + 15, [100, 100, 100, 100.5, 108, 109, 110]);
    const signal = session.evaluate([...fallingWarmup, ...today], { ...PARAMS, maxBarsSinceFlip: 3, minDistanceAtr: 0.5 });
    assert.ok(signal !== undefined, 'should fire within 3 candles of the flip');
    assert.equal(signal?.direction, 'BULLISH');
    assert.match(signal?.reasons[0] ?? '', /flip \+2b/);
  });

  it('in scout posture, rejects entry when bars since flip exceeds maxBarsSinceFlip', () => {
    const session = new StrategySession('scout', ['trend']);
    const fallingWarmup = dayBars(PREVIOUS_DAY, 9 * 60 + 15, Array.from({ length: 60 }, (_, i) => 120 - (i * 20) / 59));
    // Flip happened on 108. Followed by 4 bars: 108.5, 109, 109.5, 110 (barsSinceFlip = 4)
    const today = dayBars(SESSION_DAY, 9 * 60 + 15, [100, 100, 100, 100.5, 108, 108.5, 109, 109.5, 110]);
    const signal = session.evaluate([...fallingWarmup, ...today], { ...PARAMS, maxBarsSinceFlip: 3 });
    assert.equal(signal, undefined, 'should reject because flip is older than 3 bars');
  });

  it('in scout posture, rejects entry when distance from ST line is less than minDistanceAtr', () => {
    const session = new StrategySession('scout', ['trend']);
    const fallingWarmup = dayBars(PREVIOUS_DAY, 9 * 60 + 15, Array.from({ length: 60 }, (_, i) => 120 - (i * 20) / 59));
    const today = dayBars(SESSION_DAY, 9 * 60 + 15, [100, 100, 100, 100.5, 108]);
    // Require a very large distance (e.g. 10x ATR)
    const signal = session.evaluate([...fallingWarmup, ...today], { ...PARAMS, minDistanceAtr: 10.0 });
    assert.equal(signal, undefined, 'should reject because distance does not meet 10x ATR threshold');
  });

  it('in scout posture, fires on momentum break of recent 3-bar high', () => {
    const session = new StrategySession('scout', ['momentum']);
    const warmup = dayBars(PREVIOUS_DAY, 9 * 60 + 15, Array.from({ length: 60 }, () => 100));
    // 3 bars consolidate at 100, then 4th bar breaks out to 105
    const today = dayBars(SESSION_DAY, 9 * 60 + 15, [100, 100, 100, 105]);
    const signal = session.evaluate([...warmup, ...today], PARAMS);
    assert.ok(signal !== undefined);
    assert.equal(signal?.strategy, 'momentum');
    assert.equal(signal?.direction, 'BULLISH');
    assert.match(signal?.reasons[0] ?? '', /Momentum break/);
  });

  describe('scout families on the first bar after an overnight gap', () => {
    const OPEN_AT_START = { ...PARAMS, entryStartMinute: 9 * 60 + 15 };

    it('should not read a gap over yesterday\'s last bars as a momentum break', () => {
      const warmup = dayBars(PREVIOUS_DAY, 9 * 60 + 15, Array.from({ length: 60 }, () => 100));
      const today = dayBars(SESSION_DAY, 9 * 60 + 15, [105]);
      assert.equal(new StrategySession('scout', ['momentum']).evaluate([...warmup, ...today], OPEN_AT_START), undefined);
    });

    it('should not read a gap as an EMA cross', () => {
      const warmup = dayBars(PREVIOUS_DAY, 9 * 60 + 15, Array.from({ length: 60 }, (_, i) => 110 - (i * 10) / 59));
      const today = dayBars(SESSION_DAY, 9 * 60 + 15, [130]);
      assert.equal(new StrategySession('scout', ['ema_cross']).evaluate([...warmup, ...today], OPEN_AT_START), undefined);
    });

    it('should not read a gap as a trend continuation', () => {
      const warmup = dayBars(PREVIOUS_DAY, 9 * 60 + 15, Array.from({ length: 60 }, (_, i) => 100 + (i * 10) / 59));
      const today = dayBars(SESSION_DAY, 9 * 60 + 15, [115]);
      assert.equal(new StrategySession('scout', ['continuation']).evaluate([...warmup, ...today], OPEN_AT_START), undefined);
    });

    it('should still fire a momentum break once three bars of today exist', () => {
      const warmup = dayBars(PREVIOUS_DAY, 9 * 60 + 15, Array.from({ length: 60 }, () => 100));
      const today = dayBars(SESSION_DAY, 9 * 60 + 15, [100, 100, 100, 105]);
      assert.equal(new StrategySession('scout', ['momentum']).evaluate([...warmup, ...today], OPEN_AT_START)?.strategy, 'momentum');
    });
  });

  it('in scout posture, fires on trend continuation pullback bounce', () => {
    const session = new StrategySession('scout', ['continuation']);
    const risingWarmup = dayBars(PREVIOUS_DAY, 9 * 60 + 15, Array.from({ length: 60 }, (_, i) => 90 + (i * 20) / 59));
    // Pullback at 109, bounce at 112
    const today = dayBars(SESSION_DAY, 9 * 60 + 15, [108, 110, 109, 112]);
    const signal = session.evaluate([...risingWarmup, ...today], PARAMS);
    assert.ok(signal !== undefined);
    assert.equal(signal?.strategy, 'continuation');
    assert.equal(signal?.direction, 'BULLISH');
    assert.match(signal?.reasons[0] ?? '', /Trend continuation/);
  });
});



describe('previous-day break', () => {
  // A complete 75-bar previous session (09:15 to 15:25), closes 90→100, so its range is 89.5 to 100.5 (OTA-310).
  // Today opens inside it.
  const rising = dayBars(PREVIOUS_DAY, 9 * 60 + 15, Array.from({ length: 75 }, (_, i) => 90 + (i * 10) / 74));

  it('fires BULLISH on the bar that closes through the previous day high', () => {
    const today = dayBars(SESSION_DAY, 9 * 60 + 15, [100, 100, 100, 100.2, 101]);
    const signal = previousDayBreak([...rising, ...today], PARAMS, true);
    assert.equal(signal?.direction, 'BULLISH');
    assert.match(signal?.reasons[0] ?? '', /high 100.5/);
  });

  it('does not re-fire on a bar already beyond the level', () => {
    const today = dayBars(SESSION_DAY, 9 * 60 + 15, [100, 100, 100, 101, 101.2]);
    assert.equal(previousDayBreak([...rising, ...today], PARAMS, true), undefined);
  });

  it('fires BEARISH through the previous day low and needs a prior session', () => {
    const today = dayBars(SESSION_DAY, 9 * 60 + 15, [91, 91, 91, 90.2, 89]);
    assert.equal(previousDayBreak([...rising, ...today], PARAMS, true)?.direction, 'BEARISH');
    assert.equal(previousDayBreak(today, PARAMS, true), undefined);
  });

  it('outside scout, refuses a break against the SuperTrend', () => {
    // Day 1 establishes a downtrend 110 → 95
    const day1 = dayBars('2026-10-08', 9 * 60 + 15, Array.from({ length: 60 }, (_, i) => 110 - (i * 15) / 59));
    // Day 2 (previous day) consolidates at 96 (high 96.5, SuperTrend upper line ~99)
    const day2 = dayBars(PREVIOUS_DAY, 9 * 60 + 15, Array.from({ length: 75 }, () => 96));
    // Today breaks Day 2's high (96.5) at 97.2, while SuperTrend is still DOWN (~99)
    const today = dayBars(SESSION_DAY, 9 * 60 + 15, [96, 96, 96, 96.4, 97.2]);
    const bars = [...day1, ...day2, ...today];

    assert.equal(previousDayBreak(bars, PARAMS, true)?.direction, 'BULLISH', 'fires in scout');
    assert.equal(previousDayBreak(bars, PARAMS, false), undefined, 'refuses outside scout while SuperTrend is DOWN');
  });

  it('is off by default, and fires when named', () => {
    assert.equal(new StrategySession('scout').view().strategies.find((row) => row.id === 'prev_day')?.on, false);
    const today = dayBars(SESSION_DAY, 9 * 60 + 15, [100, 100, 100, 100.2, 101]);
    assert.equal(new StrategySession('scout', ['prev_day']).evaluate([...rising, ...today], PARAMS)?.strategy, 'prev_day');
  });
});
