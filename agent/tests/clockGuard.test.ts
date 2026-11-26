import { strict as assert } from 'node:assert';
import { describe, it } from 'node:test';
import { assertWarmupClock } from '../src/runtime/clockGuard.js';
import { bar, istEpoch, SESSION_DAY } from './support/fixtures.js';

describe('assertWarmupClock', () => {
  it('passes when there is no history yet', () => {
    assert.doesNotThrow(() => assertWarmupClock(undefined, istEpoch(SESSION_DAY, '10:00'), 5));
  });

  it('refuses bars stamped ahead of the wall clock', () => {
    const future = bar(istEpoch(SESSION_DAY, '15:10'), 1, 1, 1, 1);
    assert.throws(() => assertWarmupClock(future, istEpoch(SESSION_DAY, '09:50'), 5), /ahead of the wall clock/);
  });

  it('refuses a stale same-day series during the session', () => {
    const stale = bar(istEpoch(SESSION_DAY, '03:45'), 1, 1, 1, 1);
    assert.throws(() => assertWarmupClock(stale, istEpoch(SESSION_DAY, '10:30'), 5), /behind the wall clock/);
  });

  it('accepts a current bar and tolerates a previous-day series out of session', () => {
    assert.doesNotThrow(() => assertWarmupClock(bar(istEpoch(SESSION_DAY, '10:25'), 1, 1, 1, 1), istEpoch(SESSION_DAY, '10:30'), 5));
    const previous = bar(istEpoch('2026-10-09', '15:25'), 1, 1, 1, 1);
    assert.doesNotThrow(() => assertWarmupClock(previous, istEpoch(SESSION_DAY, '09:20'), 5));
  });
});
