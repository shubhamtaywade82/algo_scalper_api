import { strict as assert } from 'node:assert';
import { describe, it } from 'node:test';
import { analyzeOptionChain, checkOptionBuyingConfluence } from '../src/options/chainAnalyzer.js';
import type { ChainSnapshot, ChainLeg } from '../src/options/selector.js';
import { buildChainWatchView } from '../src/runtime/chainWatchView.js';
import { chainWatchLines } from '../src/ui/chainWatchPanel.js';

function leg(bid: number, ask: number, oi: number, volume = 10_000): ChainLeg {
  return { bid, ask, oi, ltp: (bid + ask) / 2, volume, securityId: 'mock' };
}

const mockChain: ChainSnapshot = {
  expiry: '2026-10-15',
  fetchedAt: 1_000,
  strikes: [
    { strike: 22_800, call: leg(140, 142, 100_000), put: leg(30, 31, 800_000) }, // Put Support Wall
    { strike: 22_850, call: leg(100, 102, 200_000), put: leg(50, 51, 300_000) },
    { strike: 22_900, call: leg(70, 71, 350_000), put: leg(75, 76, 250_000) },   // ATM
    { strike: 22_950, call: leg(45, 46, 500_000), put: leg(110, 112, 150_000) },
    { strike: 23_000, call: leg(25, 26, 900_000), put: leg(160, 162, 50_000) },  // Call Resistance Wall
  ],
};

describe('analyzeOptionChain', () => {
  it('computes total PCR, ATM PCR, and identifies OI walls correctly', () => {
    const spot = 22_905;
    const analysis = analyzeOptionChain(mockChain, spot);

    // Call OI total = 100k + 200k + 350k + 500k + 900k = 2,050k
    // Put OI total = 800k + 300k + 250k + 150k + 50k = 1,550k
    // PCR = 1550 / 2050 = 0.76
    assert.equal(analysis.pcr, 0.76);
    assert.equal(analysis.atmStrike, 22_900);

    // Max Call OI is 900k at 23000
    assert.equal(analysis.callResistance.strike, 23_000);
    assert.equal(analysis.callResistance.oi, 900_000);
    assert.equal(analysis.headroomCe, 95); // 23000 - 22905

    // Max Put OI is 800k at 22800
    assert.equal(analysis.putSupport.strike, 22_800);
    assert.equal(analysis.putSupport.oi, 800_000);
    assert.equal(analysis.headroomPe, 105); // 22905 - 22800

    // Straddle: ATM 22900 call mid (70.5) + put mid (75.5) = 146.0
    assert.equal(analysis.straddlePremium, 146.0);
    assert.equal(analysis.expectedRange.lower, 22_754.0);
    assert.equal(analysis.expectedRange.upper, 23_046.0);
  });

  it('determines sentiment score and bias', () => {
    const analysis = analyzeOptionChain(mockChain, 22_905);
    assert.ok(typeof analysis.sentimentScore === 'number');
    assert.ok(['BULLISH', 'BEARISH', 'NEUTRAL'].includes(analysis.bias));
    assert.ok(analysis.verdict.length > 0);
  });
});

describe('checkOptionBuyingConfluence', () => {
  it('vetoes CE buying when spot is within minHeadroom of Call Resistance', () => {
    // Call resistance is at 23000. Spot at 22990 is only 10 pts away (< 15 pts headroom)
    const analysis = analyzeOptionChain(mockChain, 22_990);
    const check = checkOptionBuyingConfluence(analysis, 'BULLISH', 15);
    assert.equal(check.ok, false);
    assert.match(check.reason ?? '', /only 10\.0 pts below major Call resistance/);
  });

  it('allows CE buying on breakout above Call Resistance', () => {
    // Spot at 23010 is above Call resistance at 23000 (headroomCe <= 0)
    const analysis = analyzeOptionChain(mockChain, 23_010);
    const check = checkOptionBuyingConfluence(analysis, 'BULLISH', 15);
    assert.equal(check.ok, true);
  });

  it('allows CE buying when ample headroom exists', () => {
    // Spot at 22900 has 100 pts headroom to 23000
    const analysis = analyzeOptionChain(mockChain, 22_900);
    const check = checkOptionBuyingConfluence(analysis, 'BULLISH', 15);
    assert.equal(check.ok, true);
  });

  it('vetoes PE buying when spot is within minHeadroom of Put Support', () => {
    // Put support is at 22800. Spot at 22808 is only 8 pts away (< 15 pts headroom)
    const analysis = analyzeOptionChain(mockChain, 22_808);
    const check = checkOptionBuyingConfluence(analysis, 'BEARISH', 15);
    assert.equal(check.ok, false);
    assert.match(check.reason ?? '', /only 8\.0 pts above major Put support/);
  });

  it('vetoes CE buying when PCR is severely depressed (< 0.55)', () => {
    const heavyCallChain: ChainSnapshot = {
      expiry: '2026-10-15',
      fetchedAt: 1,
      strikes: [
        { strike: 22_800, call: leg(100, 101, 1_000_000), put: leg(10, 11, 100_000) },
        { strike: 22_900, call: leg(50, 51, 1_000_000), put: leg(40, 41, 100_000) },
      ],
    };
    const analysis = analyzeOptionChain(heavyCallChain, 22_850);
    assert.ok(analysis.pcr < 0.55);
    const check = checkOptionBuyingConfluence(analysis, 'BULLISH', 15);
    assert.equal(check.ok, false);
    assert.match(check.reason ?? '', /severely depressed/);
  });
});

describe('buildChainWatchView with analysis', () => {
  it('marks RES and SUP walls on corresponding strike rows', () => {
    const view = buildChainWatchView({
      symbol: 'NIFTY',
      spot: 22_905,
      chain: mockChain,
      offsetSteps: 0,
      maxSpreadPct: 2,
      minOpenInterest: 1000,
      openPosition: undefined,
      indicators: {
        supertrend: 'UP',
        supertrendLine: 22_700,
        emaFast: 22_920,
        emaSlow: 22_880,
        orbHigh: 22_950,
        orbLow: 22_850,
        orbFormed: true,
      },
      strikeScroll: 0,
      nowMs: 2_000,
      status: 'ready',
      error: undefined,
    });

    assert.ok(view.analysis !== undefined);
    assert.equal(view.analysis.callResistance.strike, 23_000);
    assert.equal(view.analysis.putSupport.strike, 22_800);

    const resRow = view.rows.find((r) => r.strike === 23_000);
    assert.ok(resRow?.markers.includes('RES'));

    const supRow = view.rows.find((r) => r.strike === 22_800);
    assert.ok(supRow?.markers.includes('SUP'));
  });

  it('renders analysis readings in chainWatchLines', () => {
    const view = buildChainWatchView({
      symbol: 'NIFTY',
      spot: 22_905,
      chain: mockChain,
      offsetSteps: 0,
      maxSpreadPct: 2,
      minOpenInterest: 1000,
      openPosition: undefined,
      indicators: {
        supertrend: 'UP',
        supertrendLine: 22_700,
        emaFast: 22_920,
        emaSlow: 22_880,
        orbHigh: 22_950,
        orbLow: 22_850,
        orbFormed: true,
      },
      strikeScroll: 0,
      nowMs: 2_000,
      status: 'ready',
      error: undefined,
    });

    const lines = chainWatchLines(view, undefined, 140, 2, 1000);
    const text = lines.join('\n');
    assert.match(text, /straddle 146\.0/);
    assert.match(text, /PCR 0\.76/);
    assert.match(text, /R 23000/);
    assert.match(text, /S 22800/);
    assert.match(text, /Score/);
  });
});
