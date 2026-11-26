import { strict as assert } from 'node:assert';
import { describe, it } from 'node:test';
import type { ResearchSession } from '../src/research/dataset.js';
import { atmIvAt, atmIvByMinute, IV_LOOKBACK_SESSIONS, IV_MIN_HISTORY, ivBucketFor, trailingIvHistory } from '../src/research/ivContext.js';
import { bar, istEpoch } from './support/fixtures.js';

const DAY = '2026-10-12';
const MINUTES = [9 * 60 + 15, 9 * 60 + 20, 9 * 60 + 25];
const MORNING = 9 * 60 + 20;

function clock(minute: number): number {
  return istEpoch(DAY, `${String(Math.floor(minute / 60)).padStart(2, '0')}:${String(minute % 60).padStart(2, '0')}`);
}

/** Spot closes at 09:15, 09:20 and 09:25, with strikes 95, 100 and 105. Each strike's bars carry the IV the function gives. */
function session(spot: readonly [number, number, number], ivOf: (strike: number) => number | undefined): ResearchSession {
  const spotBars = MINUTES.map((minute, index) => {
    const close = spot[index] as number;
    return bar(clock(minute), close, close, close, close);
  });
  const legs = (strike: number) => {
    const iv = ivOf(strike);
    return MINUTES.map((minute) => ({ ...bar(clock(minute), 10, 10, 10, 10), ...(iv === undefined ? {} : { iv }) }));
  };
  const strikes = { '95': legs(95), '100': legs(100), '105': legs(105) };
  return { date: DAY, lotSize: 50, tickSize: 0.05, strikeStep: 5, spot: spotBars, calls: strikes, puts: strikes };
}

describe('fixed IV parameters', () => {
  it('pins the lookback, the minimum history and the tercile cuts, so they cannot drift after a look', () => {
    assert.equal(IV_LOOKBACK_SESSIONS, 20);
    assert.equal(IV_MIN_HISTORY, 10);
  });
});

describe('ATM implied volatility', () => {
  it('reads the IV of the strike nearest spot at that time', () => {
    const day = session([100, 101, 101], (strike) => (strike === 100 ? 20 : 50));
    assert.equal(atmIvAt(day, 'CE', clock(MORNING), 101), 20);
  });

  it('is undefined when the ATM bar carries no IV', () => {
    const day = session([100, 101, 101], () => undefined);
    assert.equal(atmIvAt(day, 'CE', clock(MORNING), 101), undefined);
  });

  it('maps each minute to the IV of the ATM strike at that minute', () => {
    const day = session([100, 104, 106], (strike) => (strike === 100 ? 20 : strike === 105 ? 40 : 50));
    assert.deepEqual([...atmIvByMinute(day, 'CE').entries()], [
      [555, 20],
      [560, 40],
      [565, 40],
    ]);
  });
});

describe('IV bucket', () => {
  const history = (values: readonly number[]) => values.map((value) => new Map([[555, value]]));
  const TEN = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];

  it('is UNKNOWN without the minimum history, without an IV, or with history at other minutes only', () => {
    assert.equal(ivBucketFor(history(TEN.slice(0, 9)), 555, 5), 'UNKNOWN');
    assert.equal(ivBucketFor(history(TEN), 555, undefined), 'UNKNOWN');
    assert.equal(ivBucketFor(TEN.map(() => new Map([[560, 5]])), 555, 5), 'UNKNOWN');
  });

  it('ranks the IV by its mid-rank percentile among the history, with ties at half weight', () => {
    assert.equal(ivBucketFor(history(TEN), 555, 0), 'LOW');
    assert.equal(ivBucketFor(history(TEN), 555, 3.5), 'LOW', 'three of ten below: 0.30');
    assert.equal(ivBucketFor(history(TEN), 555, 4), 'MID', 'three below and a tie: 0.35');
    assert.equal(ivBucketFor(history(TEN), 555, 5.5), 'MID');
    assert.equal(ivBucketFor(history(TEN), 555, 7), 'MID', 'six below and a tie: 0.65');
    assert.equal(ivBucketFor(history(TEN), 555, 8), 'HIGH', 'seven below and a tie: 0.75');
    assert.equal(ivBucketFor(history(TEN), 555, 11), 'HIGH');
  });
});

describe('trailing history', () => {
  it('uses at most the fixed lookback of prior sessions, and never the entry session itself', () => {
    const perSession = Array.from({ length: 30 }, (_, index) => ({ CE: new Map([[555, index]]), PE: new Map([[555, -index]]) }));
    const history = trailingIvHistory(perSession, 25);
    assert.equal(history.CE.length, IV_LOOKBACK_SESSIONS);
    assert.equal(history.CE[0]?.get(555), 25 - IV_LOOKBACK_SESSIONS);
    assert.equal(history.CE.at(-1)?.get(555), 24);
    assert.equal(history.PE.at(-1)?.get(555), -24);
    assert.equal(trailingIvHistory(perSession, 3).CE.length, 3);
  });
});
