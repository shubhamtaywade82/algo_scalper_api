import { strict as assert } from 'node:assert';
import { describe, it } from 'node:test';
import { buildChainWatchView } from '../src/runtime/chainWatchView.js';

import type { ChainLeg, ChainSnapshot } from '../src/options/selector.js';
import type { IndicatorView } from '../src/runtime/views.js';

function leg(bid: number, ask: number, oi: number): ChainLeg {
  return { bid, ask, oi, ltp: bid, volume: 100, securityId: '1' };
}

const emptyIndicators: IndicatorView = {
  emaFast: undefined,
  emaSlow: undefined,
  supertrend: undefined,
  supertrendLine: undefined,
  orbHigh: undefined,
  orbLow: undefined,
  orbFormed: false,
};

const chain: ChainSnapshot = {
  expiry: '2026-10-15',
  fetchedAt: 1_000,
  strikes: [
    { strike: 22_400, call: leg(90, 92, 200_000), put: leg(10, 11, 50_000) },
    { strike: 22_450, call: leg(60, 61, 500_000), put: leg(30, 31, 80_000) },
    { strike: 22_500, call: leg(35, 36, 120_000), put: leg(55, 56, 90_000) },
  ],
};

describe('buildChainWatchView', () => {
  it('centres strikes on ATM and marks entry legs', () => {
    const view = buildChainWatchView({
      symbol: 'NIFTY',
      spot: 22_461,
      chain,
      offsetSteps: 0,
      maxSpreadPct: 2,
      minOpenInterest: 100_000,
      openPosition: undefined,
      indicators: {
        supertrend: 'UP',
        supertrendLine: 22_300,
        emaFast: 22_500,
        emaSlow: 22_400,
        orbHigh: 22_500,
        orbLow: 22_400,
        orbFormed: true,
      },
      strikeScroll: 0,
      nowMs: 4_000,
      status: 'ready',
      error: undefined,
    });
    assert.equal(view.marketBias, 'BULLISH');
    assert.equal(view.status, 'ready');
    assert.equal(view.atmStrike, 22_450);
    assert.equal(view.bullishEntryStrike, 22_450);
    assert.equal(view.bearishEntryStrike, 22_450);
    const atmRow = view.rows.find((row) => row.markers.includes('ATM'));
    assert.ok(atmRow?.markers.includes('CE_ENTRY'));
    assert.ok(atmRow?.markers.includes('PE_ENTRY'));
    assert.equal(view.fetchedAgeMs, 3_000);
  });

  it('shifts the visible window with strikeScroll', () => {
    const wide: ChainSnapshot = {
      expiry: '2026-10-15',
      fetchedAt: 1,
      strikes: Array.from({ length: 9 }, (_, i) => {
        const strike = 22_300 + i * 50;
        return { strike, call: leg(1, 2, 10_000), put: leg(1, 2, 10_000) };
      }),
    };
    const centered = buildChainWatchView({
      symbol: 'NIFTY',
      spot: 22_450,
      chain: wide,
      offsetSteps: 0,
      maxSpreadPct: 2,
      minOpenInterest: 100,
      openPosition: undefined,
      indicators: emptyIndicators,
      strikeScroll: 0,
      nowMs: 2,
      status: 'ready',
      error: undefined,
    });
    const shifted = buildChainWatchView({
      symbol: 'NIFTY',
      spot: 22_450,
      chain: wide,
      offsetSteps: 0,
      maxSpreadPct: 2,
      minOpenInterest: 100,
      openPosition: undefined,
      indicators: emptyIndicators,
      strikeScroll: 2,
      nowMs: 2,
      status: 'ready',
      error: undefined,
    });
    assert.notDeepEqual(centered.rows.map((r) => r.strike), shifted.rows.map((r) => r.strike));
    assert.ok(shifted.rows.some((r) => r.strike > 22_450));
  });
});
