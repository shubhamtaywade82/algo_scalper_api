import { strict as assert } from 'node:assert';
import { describe, it } from 'node:test';
import type { Candle } from '../src/domain/types.js';
import { OPEN_TRAIL, onBarClosed, onTouch, specId, type TrailPosition, type TrailSpec, type TrailState } from '../src/exits/trail.js';
import { mirrorCandles } from '../src/market/stopLines.js';
import { calculateTrailingStop } from '../src/options/pricing.js';
import { SeededRng } from '../src/research/rng.js';
import { STUDY_GRID } from '../src/research/trailGrid.js';
import { bar } from './support/fixtures.js';

const BAR_MS = 300_000;
const ENTRY_INDEX = 30;

interface Path {
  readonly spot: Candle[];
  readonly premium: Candle[];
}

function randomPath(seed: number, length: number, side: 1 | -1): Path {
  const rng = new SeededRng(seed);
  const spot: Candle[] = [];
  const premium: Candle[] = [];
  let price = 23_000;
  for (let i = 0; i < length; i += 1) {
    const open = price;
    price += (rng.next() - 0.48) * 40;
    const high = Math.max(open, price) + rng.next() * 15;
    const low = Math.min(open, price) - rng.next() * 15;
    spot.push(bar(i * BAR_MS, open, high, low, price));
    const toPremium = (value: number): number => Math.max(1, 100 + 0.5 * side * (value - 23_000));
    const [pHigh, pLow] = side === 1 ? [toPremium(high), toPremium(low)] : [toPremium(low), toPremium(high)];
    premium.push(bar(i * BAR_MS, toPremium(open), pHigh, pLow, toPremium(price)));
  }
  return { spot, premium };
}

function positionFor(path: Path, side: 1 | -1): TrailPosition {
  const entryPrice = path.premium[ENTRY_INDEX]?.open ?? 100;
  return { entryPrice, initialStop: entryPrice * 0.7, side, entryTime: ENTRY_INDEX * BAR_MS, barMs: BAR_MS, halfSpreadPct: 0.5, chargesPerUnit: 0.6 };
}

/** Replays bar by bar as the study will: touch on the bar first (against the level set before it), then its close. */
function runPath(spec: TrailSpec, path: Path, position: TrailPosition): TrailState[] {
  let state = OPEN_TRAIL;
  const states: TrailState[] = [];
  for (let t = ENTRY_INDEX; t < path.spot.length; t += 1) {
    const spotBar = path.spot[t];
    const premiumBar = path.premium[t];
    if (spotBar !== undefined && premiumBar !== undefined && t > ENTRY_INDEX) {
      state = onTouch(state, 'PREMIUM', premiumBar.low, position.side);
      state = onTouch(state, 'UNDERLYING', position.side === 1 ? spotBar.low : spotBar.high, position.side);
    }
    state = onBarClosed(spec, position, state, { spot: path.spot.slice(0, t + 1), premium: path.premium.slice(0, t + 1) });
    states.push(state);
  }
  return states;
}

function isUnderlyingOnly(spec: TrailSpec): boolean {
  return ['ATR', 'SWING', 'FRACTAL', 'CHOCH'].includes(spec.kind) || ('series' in spec && spec.series === 'UNDERLYING');
}

for (const spec of STUDY_GRID) {
  describe(`trail ${specId(spec)}`, () => {
    for (const side of [1, -1] as const) {
      const path = randomPath(side === 1 ? 7 : 11, 110, side);
      const position = positionFor(path, side);
      const states = runPath(spec, path, position);

      it(`should never move a level against the position (side ${side})`, () => {
        for (let i = 1; i < states.length; i += 1) {
          for (const series of ['PREMIUM', 'UNDERLYING'] as const) {
            const before = states[i - 1]?.levels[series];
            const after = states[i]?.levels[series];
            if (before !== undefined && after !== undefined) {
              const sign = series === 'PREMIUM' ? 1 : side;
              assert.ok(sign * (after - before) >= 0, `${series} level moved from ${before} to ${after}`);
            }
          }
        }
      });

      it(`should never place a premium level below the initial stop (side ${side})`, () => {
        for (const state of states) {
          const level = state.levels.PREMIUM;
          assert.ok(level === undefined || level >= position.initialStop);
        }
      });

      it(`should give identical output on a second run (side ${side})`, () => {
        assert.deepEqual(runPath(spec, path, position), states);
      });

      it(`should ignore a bar delivered twice (side ${side})`, () => {
        const t = ENTRY_INDEX + 20;
        const bars = { spot: path.spot.slice(0, t + 1), premium: path.premium.slice(0, t + 1) };
        const before = states[t - ENTRY_INDEX - 1] ?? OPEN_TRAIL;
        const once = onBarClosed(spec, position, before, bars);
        assert.deepEqual(onBarClosed(spec, position, once, bars), once);
      });

      it(`should not let later bars change earlier levels (side ${side})`, () => {
        const cut = 60;
        const other = randomPath(99, 110, side);
        const spliced: Path = {
          spot: [...path.spot.slice(0, cut + 1), ...other.spot.slice(cut + 1)],
          premium: [...path.premium.slice(0, cut + 1), ...other.premium.slice(cut + 1)],
        };
        assert.deepEqual(runPath(spec, spliced, position).slice(0, cut - ENTRY_INDEX + 1), states.slice(0, cut - ENTRY_INDEX + 1));
      });

      it(`should not change once triggered (side ${side})`, () => {
        const index = states.findIndex((state) => state.phase === 'TRIGGERED');
        for (const state of index === -1 ? [] : states.slice(index)) {
          assert.deepEqual(state, states[index]);
        }
      });
    }

    if (isUnderlyingOnly(spec)) {
      it('should mirror the underlying level for a PE on a mirrored market', () => {
        const path = randomPath(5, 110, 1);
        const mirrored: Path = { spot: mirrorCandles(path.spot), premium: path.premium };
        const long = runPath(spec, path, positionFor(path, 1));
        const short = runPath(spec, mirrored, positionFor(path, -1));
        assert.deepEqual(
          short.map((state) => state.levels.UNDERLYING),
          long.map((state) => (state.levels.UNDERLYING === undefined ? undefined : -state.levels.UNDERLYING)),
        );
        assert.deepEqual(short.map((state) => state.phase), long.map((state) => state.phase));
      });
    }
  });
}

describe('profit-based trails', () => {
  const position: TrailPosition = { entryPrice: 100, initialStop: 70, side: 1, entryTime: 0, barMs: BAR_MS, halfSpreadPct: 0, chargesPerUnit: 0 };
  const premium = (high: number): Candle[] => [bar(0, 100, high, 99, 100)];
  const levelAt = (spec: TrailSpec, high: number): number | undefined =>
    onBarClosed(spec, position, OPEN_TRAIL, { spot: [bar(0, 1, 1, 1, 1)], premium: premium(high) }).levels.PREMIUM;

  it('should match calculateTrailingStop when the staircase steps by 1R from 1R', () => {
    for (const high of [130, 145, 160, 165, 200]) {
      const expected = calculateTrailingStop({
        entryPrice: 100, initialStopPrice: 70, currentStopPrice: 70, highWaterMark: high, trailingJump: 30, breakevenAtRr: 1, tickSize: 0.05,
      });
      assert.equal(levelAt({ kind: 'R_STAIRCASE', activationR: 1, stepR: 1, netBreakeven: false }, high), expected);
    }
  });

  it('should stay pending until peak profit reaches the activation', () => {
    const spec: TrailSpec = { kind: 'R_STAIRCASE', activationR: 1, stepR: 1, netBreakeven: false };
    assert.equal(onBarClosed(spec, position, OPEN_TRAIL, { spot: [], premium: premium(129) }).phase, 'PENDING');
  });

  it('should add charges and spread to a net breakeven', () => {
    const net = onBarClosed({ kind: 'R_STAIRCASE', activationR: 1, stepR: 1, netBreakeven: true }, { ...position, chargesPerUnit: 0.6, halfSpreadPct: 0.5 }, OPEN_TRAIL, {
      spot: [],
      premium: premium(130),
    });
    assert.equal(net.levels.PREMIUM, 100 + 0.6 + 0.5);
  });

  it('should give back the configured share of peak profit', () => {
    assert.equal(levelAt({ kind: 'GIVEBACK', activationR: 0.5, giveback: 0.5 }, 160), 130);
  });
});

describe('trail exits', () => {
  const position: TrailPosition = { entryPrice: 100, initialStop: 70, side: 1, entryTime: 3 * BAR_MS, barMs: BAR_MS, halfSpreadPct: 0, chargesPerUnit: 0 };

  it('should ignore a pre-entry high when setting a Chandelier level', () => {
    const premium = [bar(0, 100, 400, 99, 100), bar(BAR_MS, 100, 101, 99, 100), bar(2 * BAR_MS, 100, 101, 99, 100), bar(3 * BAR_MS, 100, 110, 99, 105)];
    const state = onBarClosed({ kind: 'CHANDELIER', series: 'PREMIUM', lookback: 6, period: 14, mult: 2 }, position, OPEN_TRAIL, { spot: [], premium });
    assert.ok((state.levels.PREMIUM ?? Infinity) < 110);
  });

  it('should report insufficient bars instead of a premium ATR level', () => {
    const premium = [bar(3 * BAR_MS, 100, 110, 99, 105)];
    const state = onBarClosed({ kind: 'PREMIUM_ATR', period: 14, mult: 2, activationR: 0 }, position, OPEN_TRAIL, { spot: [], premium });
    assert.equal(state.levels.PREMIUM, undefined);
    assert.equal(state.fallback, 'insufficient_bars');
  });

  it('should not exit on a wick through the average when the close stays above it', () => {
    const closes = Array.from({ length: 12 }, (_, i) => 100 + i);
    const premium = closes.map((close, i) => bar(i * BAR_MS, close, close + 1, i === 11 ? 50 : close - 1, close));
    const state = onBarClosed({ kind: 'MA_CROSS', series: 'PREMIUM', ma: 'EMA', period: 9 }, position, OPEN_TRAIL, { spot: [], premium });
    assert.equal(state.phase, 'ACTIVE');
  });

  it('should exit on the close that crosses below the average', () => {
    const closes = [...Array.from({ length: 11 }, (_, i) => 100 + i), 90];
    const premium = closes.map((close, i) => bar(i * BAR_MS, close, close + 1, close - 1, close));
    const state = onBarClosed({ kind: 'MA_CROSS', series: 'PREMIUM', ma: 'EMA', period: 9 }, position, OPEN_TRAIL, { spot: [], premium });
    assert.deepEqual(state.intent, { kind: 'CLOSE', series: 'PREMIUM', level: undefined });
  });

  it('should exit on a close below the protected low (CHoCH)', () => {
    // Bullish break at bar 8 protects the swing low of 7; entry at bar 9; bar 12 closes at 6.5.
    const spot = [
      bar(0, 10, 10, 9, 10), bar(1, 11, 11, 10, 11), bar(2, 12, 12, 11, 11.5), bar(3, 11, 11.5, 9, 9.5),
      bar(4, 9, 10, 8, 8.5), bar(5, 8, 9, 7, 8), bar(6, 9, 10, 8, 9.5), bar(7, 10, 11, 9, 10.5), bar(8, 11, 13, 10.5, 12.5),
      bar(9, 12, 12.6, 11, 11.2), bar(10, 11, 11.5, 9, 9.4), bar(11, 9, 9.5, 7.5, 7.8), bar(12, 7.5, 8, 6, 6.5),
    ].map((candle, i) => ({ ...candle, time: i * BAR_MS }));
    const premium = spot.map((candle) => bar(candle.time, 100, 101, 99, 100));
    const chochPosition = { ...position, entryTime: 9 * BAR_MS };
    const spec: TrailSpec = { kind: 'CHOCH', strength: 2 };
    const before = onBarClosed(spec, chochPosition, OPEN_TRAIL, { spot: spot.slice(0, 12), premium: premium.slice(0, 12) });
    assert.equal(before.phase, 'ACTIVE');
    const after = onBarClosed(spec, chochPosition, before, { spot, premium });
    assert.equal(after.intent?.kind, 'CLOSE');
  });

  it('should exit when the underlying Supertrend flips against a CE', () => {
    const rally = Array.from({ length: 40 }, (_, i) => bar(i * BAR_MS, 100 + i * 0.1, 100.6 + i * 0.1, 99.6 + i * 0.1, 100.2 + i * 0.1));
    const spot = [...rally, bar(40 * BAR_MS, 104, 104.2, 90, 90.5)];
    const premium = spot.map((candle) => bar(candle.time, 100, 101, 99, 100));
    const spec: TrailSpec = { kind: 'SUPERTREND', series: 'UNDERLYING', period: 10, mult: 3 };
    const stPosition = { ...position, entryTime: 35 * BAR_MS };
    assert.equal(onBarClosed(spec, stPosition, OPEN_TRAIL, { spot: rally, premium: premium.slice(0, 40) }).phase, 'ACTIVE');
    assert.equal(onBarClosed(spec, stPosition, OPEN_TRAIL, { spot, premium }).intent?.kind, 'CLOSE');
  });

  it('should report the leg that fired first in a hybrid', () => {
    const spec: TrailSpec = { kind: 'HYBRID', premium: { kind: 'GIVEBACK', activationR: 0, giveback: 0.5 }, underlying: { kind: 'DONCHIAN', series: 'UNDERLYING', bars: 3 } };
    const premium = [bar(3 * BAR_MS, 100, 160, 99, 150)];
    const spot = [bar(3 * BAR_MS, 23_000, 23_050, 22_990, 23_040)];
    const active = onBarClosed(spec, position, OPEN_TRAIL, { spot, premium });
    const hit = onTouch(onTouch(active, 'UNDERLYING', 22_980, 1), 'PREMIUM', 120, 1);
    assert.deepEqual(hit.intent, { kind: 'TOUCH', series: 'UNDERLYING', level: 22_990 });
  });

  it('should exit at the touch of the level and not before', () => {
    const active = onBarClosed({ kind: 'GIVEBACK', activationR: 0, giveback: 0.5 }, position, OPEN_TRAIL, { spot: [], premium: [bar(3 * BAR_MS, 100, 160, 99, 150)] });
    assert.equal(onTouch(active, 'PREMIUM', 130.05, 1).phase, 'ACTIVE');
    assert.equal(onTouch(active, 'PREMIUM', 130, 1).phase, 'TRIGGERED');
  });
});
