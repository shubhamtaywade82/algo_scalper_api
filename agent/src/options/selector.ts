import type { Direction, OptionContract, OptionQuote, OptionType } from '../domain/types.js';
import { dayDifference } from '../time/calendar.js';

/** Leg of one strike, as normalised from the option-chain response. Missing fields stay undefined. */
export interface ChainLeg {
  readonly ltp: number | undefined;
  readonly bid: number | undefined;
  readonly ask: number | undefined;
  readonly oi: number | undefined;
  readonly volume: number | undefined;
  readonly securityId: string | undefined;
}

export interface ChainStrike {
  readonly strike: number;
  readonly call: ChainLeg | undefined;
  readonly put: ChainLeg | undefined;
}

export interface ChainSnapshot {
  readonly expiry: string;
  readonly fetchedAt: number;
  readonly strikes: readonly ChainStrike[];
}

export type SelectionRejection =
  | 'CHAIN_EMPTY'
  | 'STRIKE_STEP_UNKNOWN'
  | 'NO_CONTRACT_AT_STRIKE'
  | 'LEG_MISSING'
  | 'SECURITY_ID_MISMATCH'
  | 'QUOTE_MISSING'
  | 'SPREAD_TOO_WIDE'
  | 'OPEN_INTEREST_TOO_LOW'
  | 'VOLUME_TOO_LOW';

export interface SelectionInput {
  readonly spot: number;
  readonly direction: Direction;
  readonly expiry: string;
  readonly chain: ChainSnapshot;
  /** Master-list contracts for this underlying and expiry. */
  readonly contracts: readonly OptionContract[];
  readonly offsetSteps: number;
  readonly maxSpreadPct: number;
  readonly minOpenInterest: number;
  readonly minVolume: number;
}

export type SelectionResult =
  | {
      readonly ok: true;
      readonly contract: OptionContract;
      readonly quote: OptionQuote;
      readonly atmStrike: number;
      readonly strikeStep: number;
    }
  | { readonly ok: false; readonly code: SelectionRejection; readonly detail: string };

export function directionToOptionType(direction: Direction): OptionType {
  return direction === 'BULLISH' ? 'CE' : 'PE';
}

const EPSILON = 1e-6;

export function nearestAtmStrike(spot: number, strikes: readonly number[]): number | undefined {
  if (strikes.length === 0) {
    return undefined;
  }
  let atmStrike = strikes[0] as number;
  for (const strike of strikes) {
    if (Math.abs(strike - spot) < Math.abs(atmStrike - spot) - EPSILON) {
      atmStrike = strike;
    }
  }
  return atmStrike;
}

export function minStrikeStep(strikes: readonly number[]): number | undefined {
  let strikeStep = Number.POSITIVE_INFINITY;
  for (let i = 1; i < strikes.length; i += 1) {
    const gap = (strikes[i] as number) - (strikes[i - 1] as number);
    if (gap > EPSILON && gap < strikeStep) {
      strikeStep = gap;
    }
  }
  return Number.isFinite(strikeStep) ? strikeStep : undefined;
}

export function targetEntryStrike(atmStrike: number, strikeStep: number, direction: Direction, offsetSteps: number): number {
  const sign = directionToOptionType(direction) === 'CE' ? 1 : -1;
  return Number((atmStrike + sign * offsetSteps * strikeStep).toFixed(2));
}

/**
 * Chooses the option to buy for a directional signal: CE for bullish, PE for
 * bearish. Strike = ATM ± offset × step, where the sign follows the option
 * type so a positive offset is always further out-of-the-money. Every check
 * fails closed: a missing quote, leg or security-id mismatch rejects the trade.
 */
export function selectContract(input: SelectionInput): SelectionResult {
  const optionType = directionToOptionType(input.direction);
  const strikes = [...new Set(input.chain.strikes.map((row) => row.strike))].sort((a, b) => a - b);
  if (strikes.length === 0) {
    return { ok: false, code: 'CHAIN_EMPTY', detail: `no strikes in chain for ${input.expiry}` };
  }

  const atmStrike = nearestAtmStrike(input.spot, strikes);
  if (atmStrike === undefined) {
    return { ok: false, code: 'CHAIN_EMPTY', detail: `no strikes in chain for ${input.expiry}` };
  }
  const strikeStep = minStrikeStep(strikes);
  if (strikeStep === undefined) {
    return { ok: false, code: 'STRIKE_STEP_UNKNOWN', detail: 'chain has fewer than two distinct strikes' };
  }

  const targetStrike = targetEntryStrike(atmStrike, strikeStep, input.direction, input.offsetSteps);

  const contract = input.contracts.find(
    (candidate) =>
      candidate.optionType === optionType &&
      candidate.expiry === input.expiry &&
      Math.abs(candidate.strike - targetStrike) < EPSILON,
  );
  if (contract === undefined) {
    return {
      ok: false,
      code: 'NO_CONTRACT_AT_STRIKE',
      detail: `no ${optionType} contract at ${targetStrike} expiring ${input.expiry} in scrip master`,
    };
  }

  const row = input.chain.strikes.find((candidate) => Math.abs(candidate.strike - targetStrike) < EPSILON);
  const leg = optionType === 'CE' ? row?.call : row?.put;
  if (leg === undefined) {
    return { ok: false, code: 'LEG_MISSING', detail: `chain has no ${optionType} leg at ${targetStrike}` };
  }
  if (leg.securityId !== undefined && leg.securityId !== contract.securityId) {
    return {
      ok: false,
      code: 'SECURITY_ID_MISMATCH',
      detail: `chain security id ${leg.securityId} differs from master ${contract.securityId}`,
    };
  }

  const { bid, ask, ltp } = leg;
  if (bid === undefined || ask === undefined || ltp === undefined || !(bid > 0) || !(ask >= bid) || !(ltp > 0)) {
    return { ok: false, code: 'QUOTE_MISSING', detail: `incomplete two-sided quote for ${contract.symbol}` };
  }
  const mid = (bid + ask) / 2;
  const spreadPct = ((ask - bid) / mid) * 100;
  if (spreadPct > input.maxSpreadPct) {
    return {
      ok: false,
      code: 'SPREAD_TOO_WIDE',
      detail: `spread ${spreadPct.toFixed(2)}% exceeds ${input.maxSpreadPct}% on ${contract.symbol}`,
    };
  }
  if ((leg.oi ?? 0) < input.minOpenInterest) {
    return { ok: false, code: 'OPEN_INTEREST_TOO_LOW', detail: `OI ${leg.oi ?? 0} below ${input.minOpenInterest}` };
  }
  if ((leg.volume ?? 0) < input.minVolume) {
    return { ok: false, code: 'VOLUME_TOO_LOW', detail: `volume ${leg.volume ?? 0} below ${input.minVolume}` };
  }

  return {
    ok: true,
    contract,
    quote: {
      ltp,
      bid,
      ask,
      oi: leg.oi,
      volume: leg.volume,
      observedAt: input.chain.fetchedAt,
    },
    atmStrike,
    strikeStep,
  };
}

/**
 * Earliest expiry between `minDaysToExpiry` and optional `maxDaysToExpiry` calendar days away.
 * A ceiling prevents buying sluggish, high-decay contracts (e.g. 8+ DTE) on intraday momentum setups.
 */
export function pickExpiry(
  expiries: readonly string[],
  todayKey: string,
  minDaysToExpiry: number,
  maxDaysToExpiry?: number,
): string | undefined {
  const eligible = expiries
    .filter((expiry) => /^\d{4}-\d{2}-\d{2}$/.test(expiry))
    .filter((expiry) => {
      const days = dayDifference(todayKey, expiry);
      return days >= minDaysToExpiry && (maxDaysToExpiry === undefined || maxDaysToExpiry <= 0 || days <= maxDaysToExpiry);
    })
    .sort();
  return eligible[0];
}
