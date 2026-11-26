import { strict as assert } from 'node:assert';
import { describe, it } from 'node:test';
import type { Candle } from '../src/domain/types.js';
import { contextVerdict, marketContext, marketStructure, structureTurnedAgainst, type MarketContext } from '../src/strategy/marketContext.js';
import { istEpoch } from './support/fixtures.js';

const START = istEpoch('2026-10-23', '09:15');

function barsOf(closes: readonly number[], wick = 0.5): Candle[] {
  return closes.map((close, i) => ({
    time: START + i * 5 * 60_000,
    open: closes[i - 1] ?? close,
    high: close + wick,
    low: close - wick,
    close,
    volume: 0,
  }));
}

function context(overrides: Partial<MarketContext>): MarketContext {
  return {
    dayTrend: 'NEUTRAL',
    dayMoveAtr: 0,
    regime: 'TRENDING',
    efficiency: 0.5,
    structure: { trend: 'NEUTRAL', lastSwingHigh: undefined, lastSwingLow: undefined, shift: undefined },
    ...overrides,
  };
}

describe('marketStructure', () => {
  it('should mark a shift when a close breaks the last swing low of a bullish structure', () => {
    // Swing high 14.5 (bar 2), swing low 9.5 (bar 4); bar 7 breaks 14.5 upward, bar 11 breaks 9.5 downward.
    const closes = [10, 12, 14, 12, 10, 12, 14, 16, 14, 12, 10, 8];
    const bullish = marketStructure(barsOf(closes.slice(0, 8)));
    assert.equal(bullish.trend, 'BULLISH');
    assert.equal(bullish.shift, undefined, 'the first break out of no structure is not a shift');

    const structure = marketStructure(barsOf(closes));
    assert.equal(structure.trend, 'BEARISH');
    assert.equal(structure.lastSwingHigh, 16.5);
    assert.equal(structure.lastSwingLow, 9.5);
    assert.deepEqual(structure.shift && { direction: structure.shift.direction, barsAgo: structure.shift.barsAgo }, { direction: 'BEARISH', barsAgo: 0 });
    assert.equal(structureTurnedAgainst(structure, 'BULLISH'), true, 'a held call is closed');
    assert.equal(structureTurnedAgainst(structure, 'BEARISH'), false, 'a held put is kept');
  });
});

describe('marketContext', () => {
  it('should read a steady climb from the open as a bullish trending day', () => {
    const closes = Array.from({ length: 20 }, (_, i) => 100 + i * 2);
    const ctx = marketContext(barsOf(closes));
    assert.equal(ctx.dayTrend, 'BULLISH');
    assert.equal(ctx.regime, 'TRENDING');
    assert.ok(ctx.dayMoveAtr > 1);
  });

  it('should read a back-and-forth day as ranging', () => {
    const closes = Array.from({ length: 20 }, (_, i) => 100 + (i % 2 === 0 ? 0 : 3));
    assert.equal(marketContext(barsOf(closes)).regime, 'RANGING');
  });
});

describe('contextVerdict', () => {
  const bullishStructure = { trend: 'BULLISH' as const, lastSwingHigh: 110, lastSwingLow: 100, shift: undefined };

  it('should veto a call against a bearish structure, however the rest votes', () => {
    const verdict = contextVerdict(
      context({ dayTrend: 'BULLISH', structure: { ...bullishStructure, trend: 'BEARISH' } }),
      'BULLISH',
      'BULLISH',
    );
    assert.equal(verdict.ok, false);
    assert.match(verdict.reason, /structure is BEARISH/);
  });

  it('should take a with-trend entry in a trending market', () => {
    const verdict = contextVerdict(context({ dayTrend: 'BULLISH', structure: bullishStructure }), 'BULLISH', 'NEUTRAL');
    assert.equal(verdict.ok, true);
    assert.equal(verdict.score, 2);
  });

  it('should need more agreement in a ranging market, which a fresh shift can supply', () => {
    const ranging = context({ regime: 'RANGING', structure: bullishStructure });
    assert.equal(contextVerdict(ranging, 'BULLISH', 'NEUTRAL').ok, false);
    const shifted = context({ regime: 'RANGING', structure: { ...bullishStructure, shift: { direction: 'BULLISH', barTime: START, barsAgo: 1 } } });
    assert.equal(contextVerdict(shifted, 'BULLISH', 'NEUTRAL').ok, true);
  });

  it('should reject a call against a falling day when only one fresh shift supports it', () => {
    // NIFTY 13:40 on 2026-10-23: day -4.4 ATR, one spike turned structure up and made the market read as trending.
    const spike = { ...bullishStructure, shift: { direction: 'BULLISH' as const, barTime: START, barsAgo: 0 } };
    const verdict = contextVerdict(context({ dayTrend: 'BEARISH', regime: 'TRENDING', structure: spike }), 'BULLISH', 'NEUTRAL');
    assert.equal(verdict.ok, false);
    assert.equal(verdict.required, 2);
    assert.equal(contextVerdict(context({ dayTrend: 'BEARISH', regime: 'TRENDING', structure: spike }), 'BULLISH', 'BULLISH').ok, true, 'the chain can supply the missing vote');
  });
});
