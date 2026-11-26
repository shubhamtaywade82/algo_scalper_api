import { strict as assert } from 'node:assert';
import { describe, it } from 'node:test';
import type { Candle } from '../src/domain/types.js';
import { expiryBucket, structureAlignment, volatilityBucket } from '../src/research/tradeFeatures.js';
import type { StructureState } from '../src/strategy/marketContext.js';
import { bar } from './support/fixtures.js';

/** OTA-309. Context features use only the history known at the signal bar, and say UNKNOWN when they cannot know. */

/** Bars whose range follows `rangeAt`, around a flat close of 100. */
function bars(count: number, rangeAt: (i: number) => number): Candle[] {
  return Array.from({ length: count }, (_, i) => {
    const range = rangeAt(i);
    return bar(i * 60_000, 100, 100 + range / 2, 100 - range / 2, 100);
  });
}

const STRUCTURE: StructureState = { trend: 'BULLISH', lastSwingHigh: 101, lastSwingLow: 99, shift: undefined };

describe('volatility feature (OTA-309)', () => {
  it('is UNKNOWN until there is enough ATR history for a percentile to mean anything', () => {
    assert.equal(volatilityBucket(bars(20, () => 1)), 'UNKNOWN');
  });

  it('is LOW when the ATR is at the bottom of its own history, as after ranges have been shrinking', () => {
    assert.equal(volatilityBucket(bars(80, (i) => 3 - i / 40)), 'LOW');
  });

  it('is HIGH when the ATR is at the top of its own history, as after ranges have been growing', () => {
    assert.equal(volatilityBucket(bars(80, (i) => 1 + i / 40)), 'HIGH');
  });

  it('uses only the bars it is given, so a later spike cannot change an earlier bucket', () => {
    const calm = bars(80, (i) => 3 - i / 40);
    const spiked = [...calm, ...bars(20, () => 50)];
    assert.equal(volatilityBucket(calm), 'LOW', 'the bucket at the signal bar is fixed by the bars up to it');
    assert.notEqual(volatilityBucket(spiked), 'LOW');
  });
});

describe('structure feature (OTA-309)', () => {
  it('is UNKNOWN until the structure has both a swing high and a swing low', () => {
    assert.equal(structureAlignment({ ...STRUCTURE, lastSwingHigh: undefined }, 'BULLISH'), 'UNKNOWN');
    assert.equal(structureAlignment({ ...STRUCTURE, lastSwingLow: undefined }, 'BEARISH'), 'UNKNOWN');
  });

  it('is WITH or AGAINST the trade direction, and NEUTRAL when the structure has no trend', () => {
    assert.equal(structureAlignment(STRUCTURE, 'BULLISH'), 'WITH');
    assert.equal(structureAlignment(STRUCTURE, 'BEARISH'), 'AGAINST');
    assert.equal(structureAlignment({ ...STRUCTURE, trend: 'NEUTRAL' }, 'BULLISH'), 'NEUTRAL');
  });
});

describe('expiry feature (OTA-309)', () => {
  it('marks the expiry day, days 1 and 2 before expiry as NEAR, and 3 or more as FAR', () => {
    assert.equal(expiryBucket('2026-10-13', '2026-10-13'), 'EXPIRY');
    assert.equal(expiryBucket('2026-10-12', '2026-10-13'), 'NEAR');
    assert.equal(expiryBucket('2026-10-11', '2026-10-13'), 'NEAR');
    assert.equal(expiryBucket('2026-10-10', '2026-10-13'), 'FAR');
  });

  it('is UNKNOWN when the session has no expiry on record, and when the expiry is before the session', () => {
    assert.equal(expiryBucket('2026-10-12', undefined), 'UNKNOWN');
    assert.equal(expiryBucket('2026-10-14', '2026-10-13'), 'UNKNOWN');
  });
});
