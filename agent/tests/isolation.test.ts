import { strict as assert } from 'node:assert';
import { describe, it } from 'node:test';
import type { Candle, Signal } from '../src/domain/types.js';
import { SeededRng } from '../src/research/rng.js';
import { createShadowTally, shadowObserver } from '../src/research/shadow.js';
import type { OrbSupertrendParams } from '../src/strategy/orbSupertrend.js';
import { StrategySession, type StrategyId } from '../src/strategy/session.js';
import { bar, istEpoch, SESSION_DAY } from './support/fixtures.js';

/** OTA-307. Research replays each family alone; first-match credits only the earliest family in the catalogue. */

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

const clock = (minute: number): string => `${String(Math.floor(minute / 60)).padStart(2, '0')}:${String(minute % 60).padStart(2, '0')}`;

/** A seeded five-minute random walk over one session, 09:15 to 14:30. */
function walk(seed: number): Candle[] {
  const rng = new SeededRng(seed);
  let close = 100;
  return Array.from({ length: 63 }, (_, i) => {
    const open = close;
    close = Math.max(50, close + (rng.next() - 0.5) * 2);
    return bar(istEpoch(SESSION_DAY, clock(9 * 60 + 15 + i * 5)), open, Math.max(open, close) + 0.3, Math.min(open, close) - 0.3, close);
  });
}

/** The first prefix, on any seed, where two or more families signal on its last bar inside the entry window. */
function findMultiSignal(): { bars: Candle[]; candidates: Array<Signal & { strategy: StrategyId }> } | undefined {
  for (let seed = 1; seed <= 400; seed += 1) {
    const bars = walk(seed);
    for (let end = 20; end <= bars.length; end += 1) {
      const lastMinute = 9 * 60 + 15 + (end - 1) * 5;
      if (lastMinute < PARAMS.entryStartMinute || lastMinute >= PARAMS.entryEndMinute) {
        continue;
      }
      const prefix = bars.slice(0, end);
      const candidates = new StrategySession('aligned').candidates(prefix, PARAMS) as Array<Signal & { strategy: StrategyId }>;
      if (candidates.length >= 2) {
        return { bars: prefix, candidates };
      }
    }
  }
  return undefined;
}

describe('per-strategy isolation (OTA-307)', () => {
  it('replays a family alone, so a signal that first-match hides on the same bar is credited to that family', () => {
    const found = findMultiSignal();
    assert.ok(found, 'some seeded walk has two families signalling on one bar');
    const [earliest, hidden] = found.candidates;
    assert.ok(earliest !== undefined && hidden !== undefined);
    assert.notEqual(earliest.strategy, hidden.strategy);

    const combined = new StrategySession('aligned').evaluate(found.bars, PARAMS);
    assert.equal(combined?.strategy, earliest.strategy, 'the live first-match credits the earliest family');

    const alone = new StrategySession('aligned', [hidden.strategy]).evaluate(found.bars, PARAMS);
    assert.equal(alone?.strategy, hidden.strategy, 'replayed alone, the hidden family is credited');
    assert.equal(alone?.direction, hidden.direction);
    assert.equal(alone?.barTime, hidden.barTime);
  });

  it('lists every enabled family that signals, in catalogue order, without changing what evaluate returns', () => {
    const found = findMultiSignal();
    assert.ok(found);
    const session = new StrategySession('aligned');
    assert.deepEqual(
      session.candidates(found.bars, PARAMS).map((signal) => signal.strategy),
      found.candidates.map((signal) => signal.strategy),
    );
    assert.equal(session.evaluate(found.bars, PARAMS)?.strategy, found.candidates[0]?.strategy);
  });

  it('counts the families first-match hid, and the family it credited, on every entry bar', () => {
    const tally = createShadowTally();
    const observer = shadowObserver(tally);
    const range = { underlying: 'NIFTY', direction: 'BULLISH' as const, barTime: 1, spot: 1, reasons: [], strategy: 'range' };
    const momentum = { ...range, strategy: 'momentum' };
    observer.onEntryBar([range, momentum], range);
    observer.onEntryBar([momentum], momentum);
    observer.onEntryBar([], undefined);
    assert.equal(tally.entryBars, 3);
    assert.equal(tally.multiSignalBars, 1);
    assert.equal(tally.credited['range'], 1);
    assert.equal(tally.hidden['momentum'], 1);
    assert.equal(tally.hidden['range'], undefined, 'the credited family is not counted as hidden');
  });
});
