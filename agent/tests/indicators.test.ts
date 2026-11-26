import { strict as assert } from 'node:assert';
import { describe, it } from 'node:test';
import { adaptiveSuperTrend, efficiencyRatio, ema, superTrend, wilderAtr } from '../src/market/indicators.js';
import { bar } from './support/fixtures.js';

describe('indicators', () => {
  it('EMA of a constant series is that constant', () => {
    assert.equal(ema(Array.from({ length: 30 }, () => 100), 9), 100);
  });

  it('EMA is undefined until the seed window is full', () => {
    assert.equal(ema([1, 2, 3], 5), undefined);
    assert.throws(() => ema([1, 2, 3], 0), RangeError);
  });

  it('EMA moves toward a step change with the standard smoothing factor', () => {
    const values = [...Array.from({ length: 9 }, () => 10), 20];
    const alpha = 2 / (9 + 1);
    const expected = 20 * alpha + 10 * (1 - alpha);
    assert.ok(Math.abs((ema(values, 9) ?? NaN) - expected) < 1e-9);
  });

  it('Wilder ATR equals the true range for constant-range bars', () => {
    const candles = Array.from({ length: 20 }, (_, i) => bar(i, 100, 101, 99, 100));
    const atr = wilderAtr(candles, 5);
    assert.equal(atr[3], undefined);
    assert.ok(Math.abs((atr[19] ?? NaN) - 2) < 1e-9);
  });

  it('SuperTrend reports UP on a persistent rally and DOWN on a persistent sell-off', () => {
    const rally = Array.from({ length: 60 }, (_, i) => bar(i, 100 + i, 101 + i, 99 + i, 100.5 + i));
    const selloff = Array.from({ length: 60 }, (_, i) => bar(i, 200 - i, 201 - i, 199 - i, 199.5 - i));
    assert.equal(superTrend(rally, 10, 3)?.trend, 'UP');
    assert.equal(superTrend(selloff, 10, 3)?.trend, 'DOWN');
  });

  it('SuperTrend flips when price closes through the active band', () => {
    const up = Array.from({ length: 40 }, (_, i) => bar(i, 100 + i * 0.1, 100.6 + i * 0.1, 99.6 + i * 0.1, 100.2 + i * 0.1));
    const crash = [...up, bar(40, 104, 104.2, 90, 90.5)];
    const before = superTrend(up, 10, 3);
    const after = superTrend(crash, 10, 3);
    assert.equal(before?.trend, 'UP');
    assert.equal(after?.trend, 'DOWN');
    assert.equal(after?.flipped, true);
  });

  it('efficiencyRatio reports 1.0 for straight directional run and 0.0 for chop', () => {
    const straight = Array.from({ length: 20 }, (_, i) => bar(i, 100 + i * 2, 101 + i * 2, 99 + i * 2, 100 + i * 2));
    assert.ok(Math.abs(efficiencyRatio(straight, 15, 10) - 1.0) < 1e-9);

    const chop = Array.from({ length: 20 }, (_, i) => bar(i, 100, 101, 99, i % 2 === 0 ? 102 : 100));
    assert.ok(efficiencyRatio(chop, 15, 10) < 0.2);
  });

  it('adaptiveSuperTrend adapts multiplier and detects flips accurately', () => {
    const rally = Array.from({ length: 60 }, (_, i) => bar(i * 300, 100 + i * 2, 101 + i * 2, 99 + i * 2, 100.5 + i * 2));
    const reversal = [...rally, bar(60 * 300, 220, 220.5, 180, 181)];
    const state = adaptiveSuperTrend(rally, 10, 3);
    const flippedState = adaptiveSuperTrend(reversal, 10, 3);

    assert.equal(state?.trend, 'UP');
    assert.equal(flippedState?.trend, 'DOWN');
    assert.equal(flippedState?.flipped, true);
    assert.equal(flippedState?.barsSinceFlip, 0);
    assert.equal(flippedState?.flipBarTime, 60 * 300);
    assert.ok((flippedState?.distanceAtr ?? 0) > 0.5);

    // One more bar in the same trend increases barsSinceFlip
    const continuation = [...reversal, bar(61 * 300, 180, 181, 178, 179)];
    const contState = adaptiveSuperTrend(continuation, 10, 3);
    assert.equal(contState?.trend, 'DOWN');
    assert.equal(contState?.flipped, false);
    assert.equal(contState?.barsSinceFlip, 1);
    assert.equal(contState?.flipBarTime, 60 * 300);
  });
});

