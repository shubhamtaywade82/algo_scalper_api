import { strict as assert } from 'node:assert';
import { describe, it } from 'node:test';
import { pickExpiry, selectContract, type ChainLeg, type ChainSnapshot, type SelectionInput } from '../src/options/selector.js';
import { contract } from './support/fixtures.js';

const LIQUID: ChainLeg = { ltp: 100.5, bid: 100, ask: 101, oi: 500_000, volume: 10_000, securityId: undefined };

function chainWith(legOverrides: Partial<Record<'call' | 'put', ChainLeg | undefined>> = {}): ChainSnapshot {
  const strikes = [22_400, 22_450, 22_500].map((strike) => ({
    strike,
    call: { ...LIQUID, securityId: `CE${strike}` },
    put: { ...LIQUID, securityId: `PE${strike}` },
  }));
  return {
    expiry: '2026-10-15',
    fetchedAt: 1_000,
    strikes: strikes.map((row) => ({ ...row, ...legOverrides })),
  };
}

const CONTRACTS = [22_400, 22_450, 22_500].flatMap((strike) => [
  contract({ optionType: 'CE', strike, securityId: `CE${strike}` }),
  contract({ optionType: 'PE', strike, securityId: `PE${strike}` }),
]);

function input(overrides: Partial<SelectionInput> = {}): SelectionInput {
  return {
    spot: 22_453,
    direction: 'BULLISH',
    expiry: '2026-10-15',
    chain: chainWith(),
    contracts: CONTRACTS,
    offsetSteps: 0,
    maxSpreadPct: 2,
    minOpenInterest: 10_000,
    minVolume: 1_000,
    ...overrides,
  };
}

describe('selectContract', () => {
  it('buys the ATM call for a bullish signal', () => {
    const result = selectContract(input());
    assert.equal(result.ok, true);
    if (result.ok) {
      assert.equal(result.contract.optionType, 'CE');
      assert.equal(result.contract.strike, 22_450);
      assert.equal(result.strikeStep, 50);
      assert.equal(result.quote.ask, 101);
    }
  });

  it('buys the ATM put for a bearish signal', () => {
    const result = selectContract(input({ direction: 'BEARISH' }));
    assert.equal(result.ok && result.contract.optionType, 'PE');
  });

  it('treats a positive offset as further out-of-the-money for both option types', () => {
    const call = selectContract(input({ offsetSteps: 1 }));
    const put = selectContract(input({ offsetSteps: 1, direction: 'BEARISH' }));
    assert.equal(call.ok && call.contract.strike, 22_500);
    assert.equal(put.ok && put.contract.strike, 22_400);
  });

  it('rejects when the chain has no strikes', () => {
    const result = selectContract(input({ chain: { expiry: '2026-10-15', fetchedAt: 1, strikes: [] } }));
    assert.equal(result.ok, false);
    assert.equal(!result.ok && result.code, 'CHAIN_EMPTY');
  });

  it('rejects when the scrip master has no contract at the target strike', () => {
    const result = selectContract(input({ contracts: CONTRACTS.filter((c) => c.strike !== 22_450) }));
    assert.equal(!result.ok && result.code, 'NO_CONTRACT_AT_STRIKE');
  });

  it('rejects a chain security id that disagrees with the scrip master', () => {
    const chain = chainWith({ call: { ...LIQUID, securityId: 'WRONG' } });
    const result = selectContract(input({ chain }));
    assert.equal(!result.ok && result.code, 'SECURITY_ID_MISMATCH');
  });

  it('rejects a missing leg, an incomplete quote, and a crossed quote', () => {
    assert.equal(!selectContract(input({ chain: chainWith({ call: undefined }) })).ok, true);
    const noAsk = selectContract(input({ chain: chainWith({ call: { ...LIQUID, ask: undefined } }) }));
    assert.equal(!noAsk.ok && noAsk.code, 'QUOTE_MISSING');
    const crossed = selectContract(input({ chain: chainWith({ call: { ...LIQUID, bid: 102, ask: 101 } }) }));
    assert.equal(!crossed.ok && crossed.code, 'QUOTE_MISSING');
  });

  it('rejects a wide spread, thin open interest, and thin volume', () => {
    const wide = selectContract(input({ chain: chainWith({ call: { ...LIQUID, bid: 90, ask: 110 } }) }));
    assert.equal(!wide.ok && wide.code, 'SPREAD_TOO_WIDE');
    const thinOi = selectContract(input({ chain: chainWith({ call: { ...LIQUID, oi: 100 } }) }));
    assert.equal(!thinOi.ok && thinOi.code, 'OPEN_INTEREST_TOO_LOW');
    const thinVol = selectContract(input({ chain: chainWith({ call: { ...LIQUID, volume: 0 } }) }));
    assert.equal(!thinVol.ok && thinVol.code, 'VOLUME_TOO_LOW');
  });
});

describe('pickExpiry', () => {
  it('picks the nearest expiry that satisfies the minimum days-to-expiry', () => {
    const expiries = ['2026-10-20', '2026-10-13', '2026-10-15', 'bogus'];
    assert.equal(pickExpiry(expiries, '2026-10-12', 0), '2026-10-13');
    assert.equal(pickExpiry(expiries, '2026-10-12', 2), '2026-10-15');
    assert.equal(pickExpiry(expiries, '2026-10-12', 30), undefined);
  });

  it('respects maxDaysToExpiry ceiling to filter out sluggish distant contracts', () => {
    const expiries = ['2026-10-20', '2026-10-13', '2026-10-15'];
    // 2026-10-12 to 2026-10-13 is 1 day, 2026-10-15 is 3 days, 2026-10-20 is 8 days
    assert.equal(pickExpiry(expiries, '2026-10-12', 0, 4), '2026-10-13');
    assert.equal(pickExpiry(expiries, '2026-10-12', 2, 4), '2026-10-15');
    assert.equal(pickExpiry(expiries, '2026-10-12', 5, 8), '2026-10-20');
    assert.equal(pickExpiry(expiries, '2026-10-12', 5, 7), undefined);
  });
});
