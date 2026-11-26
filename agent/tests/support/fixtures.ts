import type { Candle, OptionContract, OptionSegment } from '../../src/domain/types.js';
import { IST_OFFSET_MS } from '../../src/time/ist.js';

/** Epoch ms for an IST wall-clock instant: `HH:MM` or `HH:MM:SS`. */
export function istEpoch(dateKey: string, clock: string): number {
  const time = clock.length === 5 ? `${clock}:00` : clock;
  const parsed = Date.parse(`${dateKey}T${time}Z`);
  if (Number.isNaN(parsed)) {
    throw new Error(`invalid IST clock "${clock}"`);
  }
  return parsed - IST_OFFSET_MS;
}

export function bar(time: number, open: number, high: number, low: number, close: number): Candle {
  return { time, open, high, low, close, volume: 0 };
}

export function contract(overrides: Partial<OptionContract> & Pick<OptionContract, 'optionType' | 'strike'>): OptionContract {
  return {
    underlying: 'NIFTY',
    securityId: `${overrides.optionType}${overrides.strike}`,
    exchangeSegment: 'NSE_FNO' as OptionSegment,
    symbol: `NIFTY ${overrides.strike} ${overrides.optionType}`,
    expiry: '2026-10-15',
    lotSize: 75,
    tickSize: 0.05,
    ...overrides,
  };
}

export const SESSION_DAY = '2026-10-12';
