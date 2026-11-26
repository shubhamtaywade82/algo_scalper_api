import { strict as assert } from 'node:assert';
import { describe, it } from 'node:test';
import { alma, hma, sma, wma } from '../src/market/indicators.js';
import {
  acceptedSwingLow,
  donchianLow,
  isPivotLow,
  latestFractalLow,
  mirrorCandles,
  protectedLow,
  psarAfter,
} from '../src/market/stopLines.js';
import { bar } from './support/fixtures.js';

const near = (actual: number | undefined, expected: number): void => assert.ok(Math.abs((actual ?? NaN) - expected) < 1e-9, `${actual} ≠ ${expected}`);
const lows = (values: readonly number[]) => values.map((low, i) => bar(i, low + 1, low + 2, low, low + 1));
const highs = (values: readonly number[]) => values.map((high, i) => bar(i, high - 1, high, high - 2, high - 1));

describe('moving averages', () => {
  it('should average the last n values when computing SMA', () => {
    near(sma([1, 2, 3, 4], 3), 3);
    assert.equal(sma([1, 2], 3), undefined);
  });

  it('should weight the newest value highest when computing WMA(3)', () => {
    near(wma([1, 2, 3], 3), (1 * 1 + 2 * 2 + 3 * 3) / 6);
  });

  it('should have no lag on a straight line when computing HMA', () => {
    near(hma([1, 2, 3, 4, 5], 4), 5);
    assert.equal(hma([1, 2, 3, 4], 4), undefined);
  });

  it('should equal the plain mean when ALMA weights are flat', () => {
    near(alma([1, 2, 3, 4, 5, 6, 7, 8, 9], 9, 0.85, 1e-9), 5);
  });

  it('should lean toward recent values with the default ALMA offset', () => {
    const value = alma([1, 2, 3, 4, 5, 6, 7, 8, 9], 9) ?? NaN;
    assert.ok(value > 5 && value < 9);
  });

  it('should reject a non-integer period', () => {
    assert.throws(() => sma([1, 2], 1.5), RangeError);
  });
});

describe('pivots and fractals', () => {
  it('should confirm a 5-bar fractal low only after two right-side bars close', () => {
    const bars = lows([10, 9, 8, 9, 10]);
    assert.equal(latestFractalLow(bars.slice(0, 4), 3, 2), undefined);
    assert.equal(latestFractalLow(bars, 4, 2), 8);
  });

  it('should reject a tie for a strict fractal but accept it for a swing', () => {
    const bars = lows([10, 9, 8, 8, 9, 10]);
    assert.equal(isPivotLow(bars, 2, 2, true), false);
    assert.equal(isPivotLow(bars, 2, 2, false), true);
  });

  it('should keep the higher swing low and ignore a lower one after entry', () => {
    // Swing lows at 2 (8), 6 (9) and 10 (7). Entry at bar 3.
    const bars = lows([10, 9, 8, 9, 10, 10, 9, 10, 11, 10, 7, 10, 11]);
    assert.equal(acceptedSwingLow(bars, 3, 8, 2), 9);
    assert.equal(acceptedSwingLow(bars, 3, 12, 2), 9);
  });

  it('should cap the Donchian window at the entry bar', () => {
    const bars = lows([1, 50, 51, 52]);
    assert.equal(donchianLow(bars, 1, 3, 10), 50);
  });

  it('should mirror twice to the identity', () => {
    const bars = lows([3, 4, 5]);
    assert.deepEqual(mirrorCandles(mirrorCandles(bars)), bars);
  });
});

describe('protectedLow', () => {
  it('should set the protected low to the swing low standing at the latest bullish break', () => {
    // Swing high 12 at bar 2, swing low 7 at bar 5; the close at bar 8 breaks 12.
    const bars = [
      bar(0, 10, 10, 9, 10), bar(1, 11, 11, 10, 11), bar(2, 12, 12, 11, 11.5), bar(3, 11, 11.5, 9, 9.5),
      bar(4, 9, 10, 8, 8.5), bar(5, 8, 9, 7, 8), bar(6, 9, 10, 8, 9.5), bar(7, 10, 11, 9, 10.5), bar(8, 11, 13, 10.5, 12.5),
    ];
    assert.equal(protectedLow(bars, 7, 2), undefined);
    assert.equal(protectedLow(bars, 8, 2), 7);
  });

  it('should keep the protected low when a later swing low forms without a new break', () => {
    const bars = [
      bar(0, 10, 10, 9, 10), bar(1, 11, 11, 10, 11), bar(2, 12, 12, 11, 11.5), bar(3, 11, 11.5, 9, 9.5),
      bar(4, 9, 10, 8, 8.5), bar(5, 8, 9, 7, 8), bar(6, 9, 10, 8, 9.5), bar(7, 10, 11, 9, 10.5), bar(8, 11, 13, 10.5, 12.5),
      bar(9, 12, 12.6, 11, 11.2), bar(10, 11, 11.5, 10, 10.4), bar(11, 10.5, 11.8, 10.2, 11.5), bar(12, 11.5, 12, 11, 11.8),
    ];
    assert.equal(protectedLow(bars, 12, 2), 7);
  });
});

describe('psarAfter', () => {
  const params = { af0: 0.02, step: 0.02, afMax: 0.2 };

  it('should advance by AF·(EP − SAR) and raise AF on a new extreme', () => {
    const bars = [bar(0, 9.5, 10, 9, 9.8), bar(1, 10.5, 11, 10, 10.8)];
    near(psarAfter(bars, 0, 0, 8, params), 8.04);
    near(psarAfter(bars, 0, 1, 8, params), 8.04 + 0.04 * (11 - 8.04));
  });

  it('should never place the SAR above the prior two lows', () => {
    const bars = [bar(0, 9.5, 10, 9, 9.8)];
    assert.equal(psarAfter(bars, 0, 0, 9.5, params), 9);
  });

  it('should rise monotonically and stay below the lows on a steady rally', () => {
    const bars = highs(Array.from({ length: 30 }, (_, i) => 100 + i));
    let previous = -Infinity;
    for (let last = 0; last < bars.length; last += 1) {
      const sar = psarAfter(bars, 0, last, 90, params) ?? NaN;
      assert.ok(sar >= previous && sar <= (bars[last]?.low ?? -Infinity));
      previous = sar;
    }
  });
});
