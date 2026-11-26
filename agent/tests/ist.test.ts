import { strict as assert } from 'node:assert';
import { describe, it } from 'node:test';
import {
  dhanEpochSecondsToMs,
  formatMinuteOfDay,
  isMarketSessionOpen,
  istParts,
  parseMinuteOfDay,
  shiftDateKey,
} from '../src/time/ist.js';
import { dayDifference } from '../src/time/calendar.js';
import { istEpoch } from './support/fixtures.js';

describe('IST clock', () => {
  it('maps 09:15 IST to 03:45 UTC on the same calendar date', () => {
    const parts = istParts(Date.parse('2026-10-12T03:45:00Z'));
    assert.equal(parts.date, '2026-10-12');
    assert.equal(parts.minuteOfDay, 9 * 60 + 15);
  });

  it('rolls the IST date forward across the 18:30 UTC boundary', () => {
    const parts = istParts(Date.parse('2026-10-11T18:30:00Z'));
    assert.equal(parts.date, '2026-10-12');
    assert.equal(parts.minuteOfDay, 0);
  });

  it('rejects non-finite epochs instead of producing a bogus date', () => {
    assert.throws(() => istParts(Number.NaN), RangeError);
  });

  it('parses only strict 24h HH:MM strings', () => {
    assert.equal(parseMinuteOfDay('09:15'), 555);
    assert.equal(parseMinuteOfDay(' 15:05 '), 905);
    assert.throws(() => parseMinuteOfDay('9:15'), /HH:MM/);
    assert.throws(() => parseMinuteOfDay('24:00'), /HH:MM/);
    assert.throws(() => parseMinuteOfDay('12:60'), /HH:MM/);
    assert.equal(formatMinuteOfDay(905), '15:05');
  });

  it('shifts date keys by calendar days without timezone drift', () => {
    assert.equal(shiftDateKey('2026-10-01', -2), '2026-09-29');
    assert.equal(shiftDateKey('2026-02-28', 1), '2026-03-01');
    assert.equal(dayDifference('2026-10-12', '2026-10-15'), 3);
    assert.equal(dayDifference('2026-10-15', '2026-10-12'), -3);
  });

  it('removes the IST offset only when Dhan encodes IST wall-clock into epoch seconds', () => {
    const utcSeconds = Date.parse('2026-10-12T03:45:00Z') / 1000;
    assert.equal(dhanEpochSecondsToMs(utcSeconds, false), utcSeconds * 1000);
    assert.equal(dhanEpochSecondsToMs(utcSeconds + 19_800, true), utcSeconds * 1000);
    assert.equal(istEpoch('2026-10-12', '09:15'), Date.parse('2026-10-12T03:45:00Z'));
  });

  it('identifies whether regular market session is open', () => {
    assert.equal(isMarketSessionOpen(Date.parse('2026-10-12T03:44:00Z')), false);
    assert.equal(isMarketSessionOpen(Date.parse('2026-10-12T03:45:00Z')), true);
    assert.equal(isMarketSessionOpen(Date.parse('2026-10-12T09:59:00Z')), true);
    assert.equal(isMarketSessionOpen(Date.parse('2026-10-12T10:00:00Z')), false);
    assert.equal(isMarketSessionOpen(Date.parse('2026-10-17T06:30:00Z')), false);
  });
});
