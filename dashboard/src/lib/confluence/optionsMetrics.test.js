import { describe, it, expect } from 'vitest';
import { daysToExpiry, deriveOptionsView, optionLevels } from './optionsMetrics';

const leg = (strike, type, ltp, oi) => ({ strike, type, ltp, oi, lot_size: 65 });
const chain = {
  spot: 25897, atm_strike: 25900, expiry: '2026-12-01',
  legs: [
    leg(25800, 'CE', 130, 100), leg(25800, 'PE', 40, 500),
    leg(25900, 'CE', 80, 300), leg(25900, 'PE', 70, 200),
    leg(26000, 'CE', 40, 900), leg(26000, 'PE', 120, 100)
  ]
};
const NOW = new Date('2026-11-25T06:00:00Z');

describe('deriveOptionsView', () => {
  it('should compute straddle, breakevens and implied move from ATM premiums', () => {
    const view = deriveOptionsView(chain, NOW);
    expect(view.straddle).toBe(150);
    expect(view.breakeven).toEqual({ ce: 25980, pe: 25830 });
    expect(view.impliedMove).toEqual({ up: 26047, down: 25747 });
  });

  it('should find OI walls and PCR', () => {
    const view = deriveOptionsView(chain, NOW);
    expect(view.callWall.strike).toBe(26000);
    expect(view.putWall.strike).toBe(25800);
    expect(view.pcr).toBeCloseTo(800 / 1300, 6);
  });

  it('should return null for an empty chain', () => {
    expect(deriveOptionsView({ legs: [] }, NOW)).toBeNull();
  });

  it('should skip levels that cannot be computed', () => {
    const view = deriveOptionsView({ ...chain, legs: chain.legs.filter((l) => !(l.strike === 25900 && l.type === 'PE')) }, NOW);
    const labels = optionLevels(view).map((l) => l.label);
    expect(labels).not.toContain('PE BE NaN');
    expect(labels.some((l) => l.startsWith('EM'))).toBe(false);
  });
});

describe('daysToExpiry', () => {
  it('should count calendar days in IST', () => {
    expect(daysToExpiry('2026-12-01', NOW)).toBe(6);
  });
});
