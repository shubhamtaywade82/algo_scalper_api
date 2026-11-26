import { shiftDateKey } from '../time/ist.js';

/** Dhan's rolling-option request limit, in calendar days. */
export const ROLLING_MAX_SPAN_DAYS = 30;

/** Expiry codes the rolling endpoint accepts (0 current, 1 near, 2 next). SDK 2.1.0 refuses any other. */
export const ROLLING_EXPIRY_CODES: readonly number[] = [0, 1, 2];

export interface RequestBlock {
  readonly from: string;
  /** Exclusive: Dhan's toDate is non-inclusive. */
  readonly to: string;
}

/**
 * The request blocks that cover the sessions from `fromDate` to `toDate`, both inclusive. Each block holds at most `windowDays` sessions.
 * Every block ends the day after its last session, so the final session is always requested and no session is requested twice.
 */
export function requestBlocks(fromDate: string, toDate: string, windowDays: number): RequestBlock[] {
  const out: RequestBlock[] = [];
  let first = fromDate;
  while (first <= toDate) {
    const end = shiftDateKey(first, windowDays - 1);
    const last = end < toDate ? end : toDate;
    out.push({ from: first, to: shiftDateKey(last, 1) });
    first = shiftDateKey(last, 1);
  }
  return out;
}

/** Interval strings the rolling endpoint accepts. */
export type RollingInterval = '1' | '5' | '15' | '25' | '60';

export type RollingRequiredField = 'open' | 'high' | 'low' | 'close' | 'volume' | 'strike' | 'iv' | 'oi';

export interface RollingRequestInput {
  readonly securityId: string;
  readonly exchangeSegment: 'NSE_FNO' | 'BSE_FNO';
  readonly expiryFlag: 'WEEK' | 'MONTH';
  readonly expiryCode: 0 | 1 | 2;
  readonly strike: string;
  readonly drvOptionType: 'CALL' | 'PUT';
  readonly interval: RollingInterval;
  readonly requiredData: readonly RollingRequiredField[];
  readonly block: RequestBlock;
}

/**
 * The request for one block of one strike. Typed to the literal unions in SDK 2.1.0, which are also valid in 2.0.1.
 * `autoAdjustDates` is off: the SDK would otherwise move the dates to trading days, and the block is already exact.
 */
export function rollingRequest(input: RollingRequestInput) {
  return {
    securityId: input.securityId,
    exchangeSegment: input.exchangeSegment,
    instrument: 'OPTIDX' as const,
    expiryFlag: input.expiryFlag,
    expiryCode: input.expiryCode,
    strike: input.strike,
    drvOptionType: input.drvOptionType,
    interval: input.interval,
    requiredData: [...input.requiredData],
    fromDate: input.block.from,
    toDate: input.block.to,
    autoAdjustDates: false as const,
  };
}
