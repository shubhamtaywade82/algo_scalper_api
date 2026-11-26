import { roundDownToTick, roundTripChargesInr } from '../options/pricing.js';

/**
 * OTA-311 rollout. 'off' keeps planned risk and records nothing extra. 'shadow' keeps planned risk for every decision and
 * journals the all-in figure beside it. 'enforce' sizes, gates and books open risk on the all-in figure.
 */
export type AllInRiskPolicy = 'off' | 'shadow' | 'enforce';

/**
 * What a stop can cost beyond its planned distance (OTA-311). Once triggered, a stop fills as a market order, so the
 * exit lands below the stop by the half-spread and by the stop slippage. Both are percentages of the price.
 */
export interface AdverseCosts {
  readonly halfSpreadPct: number;
  readonly stopSlippagePct: number;
}

/**
 * The adverse costs for a config. Entries are refused above maxSpreadPct, so half of it is the largest half-spread an
 * entry can have, and the stop slippage is taken as equal to it, as the replay has always done.
 */
export function adverseCostsFor(config: { readonly contract: { readonly maxSpreadPct: number } }): AdverseCosts {
  const halfSpreadPct = config.contract.maxSpreadPct / 2;
  return { halfSpreadPct, stopSlippagePct: halfSpreadPct };
}

/** The worst fill a triggered stop can get: the stop less both adverse costs, rounded down to the tick, never below one tick. */
export function stopExitPrice(stopPrice: number, costs: AdverseCosts, tickSize: number): number {
  return Math.max(tickSize, roundDownToTick(stopPrice * (1 - (costs.halfSpreadPct + costs.stopSlippagePct) / 100), tickSize));
}

export interface AllInInput {
  readonly quantity: number;
  readonly entryPrice: number;
  readonly stopPrice: number;
  readonly costs: AdverseCosts;
  readonly tickSize: number;
  readonly exchangeSegment: string;
}

/**
 * All-in adverse loss of a position whose stop fills at the worst exit the costs allow: the gross move to that exit, plus
 * the round-trip charges on it. This is what the account can lose. The planned stop distance is not.
 */
export function allInAdverseLossInr(input: AllInInput): number {
  const exitPrice = stopExitPrice(input.stopPrice, input.costs, input.tickSize);
  const gross = input.quantity * (input.entryPrice - exitPrice);
  const charges = roundTripChargesInr({
    quantity: input.quantity,
    buyPrice: input.entryPrice,
    sellPrice: exitPrice,
    exchangeSegment: input.exchangeSegment,
  });
  return Number((gross + charges).toFixed(2));
}
