import { strict as assert } from 'node:assert';
import { describe, it } from 'node:test';
import { bracketLevels, calculateTrailingStop, expirySettlementPrice, roundDownToTick, roundTripChargesInr, roundUpToTick } from '../src/options/pricing.js';
import { sizePosition } from '../src/options/sizing.js';

describe('tick rounding', () => {
  it('rounds the stop up and the target down on the tick grid', () => {
    assert.equal(roundUpToTick(70.01, 0.05), 70.05);
    assert.equal(roundDownToTick(159.99, 0.05), 159.95);
    assert.equal(roundUpToTick(70, 0.05), 70, 'exact grid values are not moved');
    assert.equal(roundUpToTick(0.1 * 3, 0.1), 0.3, 'floating-point residue is removed');
    assert.throws(() => roundUpToTick(10, 0), RangeError);
  });
});

describe('bracketLevels', () => {
  it('builds a stop at the configured percentage and a target at the configured R-multiple', () => {
    const levels = bracketLevels({ entryReference: 100, stopLossPct: 30, targetRr: 2, tickSize: 0.05 });
    assert.deepEqual(levels, { entryReference: 100, stopLossPrice: 70, targetPrice: 160, riskPerUnit: 30, trailingJump: undefined });
  });

  it('calculates trailing jump step when trailingJumpPct is configured', () => {
    const levels = bracketLevels({ entryReference: 100, stopLossPct: 30, targetRr: 2, tickSize: 0.05, trailingJumpPct: 15 });
    assert.deepEqual(levels, { entryReference: 100, stopLossPrice: 70, targetPrice: 160, riskPerUnit: 30, trailingJump: 15 });
  });

  it('returns undefined when the stop cannot be expressed on the tick grid', () => {
    assert.equal(bracketLevels({ entryReference: 0.1, stopLossPct: 30, targetRr: 2, tickSize: 0.05 }), undefined);
  });

  it('returns undefined for non-positive premiums', () => {
    assert.equal(bracketLevels({ entryReference: 0, stopLossPct: 30, targetRr: 2, tickSize: 0.05 }), undefined);
  });
});

describe('calculateTrailingStop', () => {
  const base = {
    entryPrice: 100,
    initialStopPrice: 70,
    currentStopPrice: 70,
    highWaterMark: 100,
    trailingJump: 15,
    breakevenAtRr: 1,
    tickSize: 0.05,
  };

  it('keeps the stop at initial stop before reaching 1R', () => {
    const stop = calculateTrailingStop({ ...base, highWaterMark: 125 });
    assert.equal(stop, 70, 'under 1R (130), stop remains at initial 70');
  });

  it('moves stop to breakeven when high water mark touches 1R', () => {
    const stop = calculateTrailingStop({ ...base, highWaterMark: 130 });
    assert.equal(stop, 100, 'at 1R (+30), stop moves to entry price 100');
  });

  it('steps stop up by trailingJump for gains beyond 1R', () => {
    const stop1 = calculateTrailingStop({ ...base, highWaterMark: 145 });
    assert.equal(stop1, 115, 'at 1R + 1 jump (+45), stop moves to 115');

    const stop2 = calculateTrailingStop({ ...base, highWaterMark: 160 });
    assert.equal(stop2, 130, 'at 1R + 2 jumps (+60), stop moves to 130');
  });

  it('never decreases stop even if currentStopPrice is already higher', () => {
    const stop = calculateTrailingStop({ ...base, currentStopPrice: 130, highWaterMark: 120 });
    assert.equal(stop, 130, 'stop never moves down');
  });

  it('moves stop to breakeven at fractional R (0.8R) and steps with tighter jump', () => {
    const tight = { ...base, breakevenAtRr: 0.8, trailingJump: 8 };
    // initialRisk = 30; 0.8R = 24 -> breakeven threshold = 124.
    assert.equal(calculateTrailingStop({ ...tight, highWaterMark: 123 }), 70);
    assert.equal(calculateTrailingStop({ ...tight, highWaterMark: 124 }), 100);
    assert.equal(calculateTrailingStop({ ...tight, highWaterMark: 132 }), 108);
    assert.equal(calculateTrailingStop({ ...tight, highWaterMark: 140 }), 116);
  });
});

describe('sizePosition', () => {
  const base = {
    capitalInr: 100_000,
    maxRiskPerTradePct: 1,
    availableFundsInr: 1_000_000,
    entryReference: 100,
    stopLossPrice: 70,
    lotSize: 75,
    maxLotsPerOrder: 10,
  };

  it('returns zero lots when one lot exceeds the risk budget', () => {
    const result = sizePosition(base);
    assert.equal(result.lots, 0);
    assert.equal(result.limitedBy, 'RISK');
  });

  it('floors lots to whole lots within the risk budget', () => {
    const result = sizePosition({ ...base, maxRiskPerTradePct: 5 });
    assert.equal(result.lots, 2, '5000 budget / 2250 per lot floors to 2');
    assert.equal(result.quantity, 150);
    assert.equal(result.riskInr, 4500);
    assert.ok(result.riskInr <= result.riskBudgetInr);
  });

  it('is limited by available funds when cash, not risk, binds', () => {
    const result = sizePosition({ ...base, maxRiskPerTradePct: 50, availableFundsInr: 15_000 });
    assert.equal(result.lots, 2);
    assert.equal(result.limitedBy, 'FUNDS');
  });

  it('is limited by the per-order lot cap when that binds first', () => {
    const result = sizePosition({ ...base, maxRiskPerTradePct: 50, maxLotsPerOrder: 1 });
    assert.equal(result.lots, 1);
    assert.equal(result.limitedBy, 'MAX_LOTS');
  });

  it('refuses to size a degenerate stop instead of dividing by zero', () => {
    assert.equal(sizePosition({ ...base, stopLossPrice: 100 }).lots, 0);
  });
});

describe('roundTripChargesInr', () => {
  it('should total brokerage, exchange, SEBI, STT, stamp duty and GST for an NSE round trip', () => {
    // Buy 7575, sell 12120: 40 + 6.899 + 0.020 + 18.18 + 0.227 + 8.445 = 73.77.
    assert.equal(roundTripChargesInr({ quantity: 75, buyPrice: 101, sellPrice: 161.6, exchangeSegment: 'NSE_FNO' }), 73.77);
  });

  it('should charge STT on the sell premium only, so a worthless exit pays none', () => {
    const worthless = roundTripChargesInr({ quantity: 75, buyPrice: 100, sellPrice: 0, exchangeSegment: 'NSE_FNO' });
    // 40 brokerage + 2.627 exchange + 0.0075 SEBI + 0.225 stamp + GST 7.674 on (40 + 2.627 + 0.0075).
    assert.equal(worthless, 50.53);
  });

  it('should use the BSE exchange rate for SENSEX options', () => {
    const nse = roundTripChargesInr({ quantity: 20, buyPrice: 200, sellPrice: 200, exchangeSegment: 'NSE_FNO' });
    const bse = roundTripChargesInr({ quantity: 20, buyPrice: 200, sellPrice: 200, exchangeSegment: 'BSE_FNO' });
    assert.ok(bse < nse);
  });
});

describe('expirySettlementPrice', () => {
  it('should pay intrinsic value in the money and zero out of it', () => {
    assert.equal(expirySettlementPrice('CE', 22_450, 22_512.35), 62.35);
    assert.equal(expirySettlementPrice('PE', 22_450, 22_400), 50);
    assert.equal(expirySettlementPrice('CE', 22_450, 22_400), 0);
    assert.equal(expirySettlementPrice('PE', 22_450, 22_450), 0);
  });
});
