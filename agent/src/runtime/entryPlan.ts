import type { AgentConfig } from '../config.js';
import type { OptionContract, OptionQuote, Signal } from '../domain/types.js';
import type { EntrySnapshot } from '../llm/advisor.js';
import { bracketLevels, roundDownToTick, roundUpToTick, type BracketLevels } from '../options/pricing.js';
import { dayDifference } from '../time/calendar.js';

/** A quote the entry path has confirmed is two-sided. */
export type TwoSidedQuote = OptionQuote & { readonly ask: number; readonly bid: number };

export type EntryPrices =
  | { readonly ok: true; readonly bracket: BracketLevels; readonly targetPrice: number }
  | { readonly ok: false; readonly entryLimit: number };

/**
 * Entry limit, stop and target from the ask. The entry is a LIMIT at ask × (1 + buffer), so any fill is at or
 * below it and the realised risk stays inside the budget; sizing off the bare ask with a MARKET order let a
 * slipped fill widen the fixed stop distance.
 */
export function planEntryPrices(ask: number, tickSize: number, config: Pick<AgentConfig, 'contract' | 'exits'>): EntryPrices {
  const entryLimit = roundUpToTick(ask * (1 + config.contract.entryLimitBufferPct / 100), tickSize);
  const bracket = bracketLevels({
    entryReference: entryLimit,
    stopLossPct: config.exits.stopLossPct,
    targetRr: config.exits.targetRr,
    tickSize,
    trailingJumpPct: config.exits.trailingJumpPct,
  });
  if (bracket === undefined) {
    return { ok: false, entryLimit };
  }
  const targetPrice = config.exits.runnerMode
    ? roundDownToTick(bracket.entryReference + Math.max(10 * bracket.riskPerUnit, bracket.entryReference * 5), tickSize)
    : bracket.targetPrice;
  return { ok: true, bracket, targetPrice };
}

export interface EntrySnapshotInput {
  readonly underlying: string;
  readonly signal: Signal;
  readonly contract: OptionContract;
  readonly quote: TwoSidedQuote;
  readonly expiry: string;
  readonly today: { readonly date: string; readonly minuteOfDay: number };
  readonly bracket: BracketLevels;
  readonly targetPrice: number;
  readonly lots: number;
  readonly riskInr: number;
}

/** The facts the advisor and the journal see for one entry. */
export function buildEntrySnapshot(input: EntrySnapshotInput): EntrySnapshot {
  const { quote, bracket, signal, contract } = input;
  return {
    underlying: input.underlying,
    direction: signal.direction,
    optionSymbol: contract.symbol,
    strike: contract.strike,
    expiry: input.expiry,
    daysToExpiry: dayDifference(input.today.date, input.expiry),
    minuteOfDayIst: input.today.minuteOfDay,
    spot: signal.spot,
    entryReference: bracket.entryReference,
    stopLossPrice: bracket.stopLossPrice,
    targetPrice: input.targetPrice,
    spreadPct: ((quote.ask - quote.bid) / ((quote.ask + quote.bid) / 2)) * 100,
    openInterest: quote.oi ?? 0,
    lots: input.lots,
    riskInr: input.riskInr,
    strategy: signal.strategy ?? 'unknown',
    signalReasons: signal.reasons,
  };
}
