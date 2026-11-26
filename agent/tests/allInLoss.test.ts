import { strict as assert } from 'node:assert';
import { describe, it } from 'node:test';
import { adverseCostsFor, allInAdverseLossInr, stopExitPrice } from '../src/risk/allInLoss.js';
import { roundTripChargesInr } from '../src/options/pricing.js';
import { sizePosition } from '../src/options/sizing.js';

/** OTA-311. The all-in loss is what the account can lose at a stop, not the distance the stop was planned at. */

const ZERO = { halfSpreadPct: 0, stopSlippagePct: 0 };
const SPREAD = { halfSpreadPct: 1, stopSlippagePct: 1 };

describe('all-in adverse loss (OTA-311)', () => {
  it('with no adverse costs, is the planned stop loss plus the round-trip charges on that exit', () => {
    const loss = allInAdverseLossInr({ quantity: 75, entryPrice: 100, stopPrice: 70, costs: ZERO, tickSize: 0.05, exchangeSegment: 'NSE_FNO' });
    const charges = roundTripChargesInr({ quantity: 75, buyPrice: 100, sellPrice: 70, exchangeSegment: 'NSE_FNO' });
    assert.equal(loss, Number((75 * 30 + charges).toFixed(2)));
  });

  it('charges the half-spread and the stop slippage on the exit, so the loss is larger than the planned distance', () => {
    const planned = allInAdverseLossInr({ quantity: 75, entryPrice: 100, stopPrice: 70, costs: ZERO, tickSize: 0.05, exchangeSegment: 'NSE_FNO' });
    const withCosts = allInAdverseLossInr({ quantity: 75, entryPrice: 100, stopPrice: 70, costs: SPREAD, tickSize: 0.05, exchangeSegment: 'NSE_FNO' });
    assert.ok(withCosts > planned, 'a stop that fills below its level costs more than the stop distance');
  });

  it('prices the exit at the stop less both adverse costs, rounded down to the tick, and never below one tick', () => {
    // 70 × (1 − 2%) = 68.6, which is on the 0.05 tick.
    assert.equal(stopExitPrice(70, SPREAD, 0.05), 68.6);
    // 70.03 × (1 − 2%) = 68.6294, rounded down to 68.6
    assert.equal(stopExitPrice(70.03, SPREAD, 0.05), 68.6);
    assert.equal(stopExitPrice(0.01, { halfSpreadPct: 50, stopSlippagePct: 50 }, 0.05), 0.05);
  });

  it('takes the adverse costs from the configured spread cap: half of maxSpreadPct, for both terms', () => {
    assert.deepEqual(adverseCostsFor({ contract: { maxSpreadPct: 2 } }), { halfSpreadPct: 1, stopSlippagePct: 1 });
  });

  it('sizes lots on the all-in loss per lot when given, so the budget bounds what the account can lose', () => {
    const base = { capitalInr: 230_000, maxRiskPerTradePct: 2, availableFundsInr: 1e9, entryReference: 100, stopLossPrice: 70, lotSize: 75, maxLotsPerOrder: 15 };
    assert.equal(sizePosition(base).lots, 2, 'planned: 4600 budget over 2250 per lot');
    const allIn = sizePosition({ ...base, perLotRiskInr: 2600 });
    assert.equal(allIn.lots, 1, 'all-in: 4600 budget over 2600 per lot');
    assert.equal(allIn.riskInr, 2600);
  });
});
