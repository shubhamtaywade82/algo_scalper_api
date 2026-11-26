import { strict as assert } from 'node:assert';
import { describe, it } from 'node:test';
import type { Direction } from '../src/domain/types.js';
import { simulatePortfolio, type PortfolioTrade } from '../src/research/portfolio.js';

const MINUTE = 60_000;

function trade(underlying: string, direction: Direction, entryMinute: number, exitMinute: number, netPnlInr: number, date = '2026-10-27'): PortfolioTrade {
  return {
    underlying,
    date,
    strategy: 'trend',
    direction,
    optionType: direction === 'BULLISH' ? 'CE' : 'PE',
    strike: 100,
    signalBarTime: entryMinute * MINUTE,
    entryTime: entryMinute * MINUTE,
    exitTime: exitMinute * MINUTE,
    entryLimit: 10,
    entryPrice: 10,
    initialStopPrice: 5,
    finalStopPrice: 5,
    targetPrice: 15,
    exitPrice: 10,
    lots: 1,
    quantity: 65,
    riskInr: 20_000,
    grossPnlInr: netPnlInr,
    chargesInr: 0,
    netPnlInr,
    r: netPnlInr / 20_000,
    exitReason: netPnlInr < 0 ? 'STOP_LOSS' : 'TARGET',
    ambiguousBar: false,
    gapThroughStop: false,
    context: {
      regime: 'TRENDING',
      trendAlignment: 'WITH',
      timeBucket: 'OPEN',
      expiryDay: false,
      volatility: 'UNKNOWN',
      structureAlignment: 'UNKNOWN',
      expiryBucket: 'UNKNOWN',
      ivBucket: 'UNKNOWN',
      chainBias: 'UNKNOWN',
    },
  };
}

const RULES = { dailyLossLimitInr: 40_000, maxPositionsPerSide: 1, maxOpenPositions: 6 };

describe('portfolio replay', () => {
  it('refuses a second same-side position across indices while the first is open', () => {
    const { taken, skipped } = simulatePortfolio([trade('NIFTY', 'BEARISH', 0, 20, -20_000), trade('SENSEX', 'BEARISH', 1, 30, -10_000), trade('SENSEX', 'BULLISH', 2, 30, 5_000)], RULES);
    assert.deepEqual(taken.map((t) => [t.underlying, t.direction]), [['NIFTY', 'BEARISH'], ['SENSEX', 'BULLISH']]);
    assert.equal(skipped.PER_SIDE, 1);
  });

  it('applies one daily limit to realised P&L plus every open stop, across indices, and resets each day', () => {
    const day1 = [trade('NIFTY', 'BEARISH', 0, 10, -20_000), trade('SENSEX', 'BULLISH', 11, 20, -20_000), trade('BANKNIFTY', 'BULLISH', 21, 30, 9_000)];
    const { taken, skipped } = simulatePortfolio([...day1, trade('NIFTY', 'BULLISH', 0, 5, 1_000, '2026-10-28')], { ...RULES, maxPositionsPerSide: 2 });
    assert.deepEqual(taken.map((t) => `${t.date} ${t.underlying}`), ['2026-10-27 NIFTY', '2026-10-27 SENSEX', '2026-10-28 NIFTY']);
    assert.equal(skipped.DAILY_LOSS, 1);
  });

  it('frees a slot once the earlier position has exited', () => {
    const { taken } = simulatePortfolio([trade('NIFTY', 'BEARISH', 0, 10, 1_000), trade('SENSEX', 'BEARISH', 10, 20, 1_000)], RULES);
    assert.equal(taken.length, 2);
  });
});
