export interface BracketLevels {
  readonly entryReference: number;
  readonly stopLossPrice: number;
  readonly targetPrice: number;
  /** Premium points lost per unit if the stop is hit. */
  readonly riskPerUnit: number;
  readonly trailingJump?: number | undefined;
}

function decimalPlaces(value: number): number {
  const text = value.toString();
  const dot = text.indexOf('.');
  return dot === -1 ? 0 : text.length - dot - 1;
}

/** Snaps to the tick grid and strips floating-point residue (e.g. 0.1 * 3 = 0.30000000000000004). */
function snap(steps: number, tickSize: number): number {
  return Number((steps * tickSize).toFixed(decimalPlaces(tickSize)));
}

export function roundUpToTick(price: number, tickSize: number): number {
  assertTick(tickSize);
  return snap(Math.ceil(price / tickSize - 1e-9), tickSize);
}

export function roundDownToTick(price: number, tickSize: number): number {
  assertTick(tickSize);
  return snap(Math.floor(price / tickSize + 1e-9), tickSize);
}

function assertTick(tickSize: number): void {
  if (!Number.isFinite(tickSize) || tickSize <= 0) {
    throw new RangeError(`tick size must be positive, got ${tickSize}`);
  }
}

/**
 * Stop and target for a long option bought at `entryReference`. The stop is
 * rounded up (exits no later than requested) and the target rounded down
 * (never promises more than the geometry allows). Returns undefined when the
 * tick grid cannot express a valid bracket at this premium.
 */
export function bracketLevels(input: {
  entryReference: number;
  stopLossPct: number;
  targetRr: number;
  tickSize: number;
  trailingJumpPct?: number;
}): BracketLevels | undefined {
  const { entryReference, stopLossPct, targetRr, tickSize, trailingJumpPct } = input;
  if (!Number.isFinite(entryReference) || entryReference <= 0) {
    return undefined;
  }
  const stopLossPrice = roundUpToTick(entryReference * (1 - stopLossPct / 100), tickSize);
  const riskPerUnit = Number((entryReference - stopLossPrice).toFixed(decimalPlaces(tickSize)));
  if (stopLossPrice <= 0 || riskPerUnit < tickSize) {
    return undefined;
  }
  const targetPrice = roundDownToTick(entryReference + targetRr * riskPerUnit, tickSize);
  if (targetPrice < entryReference + tickSize) {
    return undefined;
  }
  const trailingJump =
    trailingJumpPct !== undefined && trailingJumpPct > 0
      ? roundDownToTick(Math.max(tickSize, entryReference * (trailingJumpPct / 100)), tickSize)
      : undefined;
  return { entryReference, stopLossPrice, targetPrice, riskPerUnit, trailingJump };
}

export interface TrailingStopInput {
  readonly entryPrice: number;
  readonly initialStopPrice: number;
  readonly currentStopPrice: number;
  readonly highWaterMark: number;
  readonly trailingJump: number;
  readonly breakevenAtRr?: number | undefined;
  readonly tickSize: number;
}

/**
 * Trails the stop upward monotonically. Breakeven moves stop to entry when high water mark hits
 * 1R, and each jump size further in profit steps the stop up by trailingJump points.
 */
export function calculateTrailingStop(input: TrailingStopInput): number {
  const { entryPrice, initialStopPrice, currentStopPrice, highWaterMark, trailingJump, tickSize } = input;
  const breakevenAtRr = input.breakevenAtRr ?? 1;
  const initialRisk = entryPrice - initialStopPrice;
  if (initialRisk <= 0 || trailingJump <= 0 || highWaterMark < entryPrice) {
    return currentStopPrice;
  }
  const breakevenThreshold = entryPrice + breakevenAtRr * initialRisk;
  let targetStop = currentStopPrice;
  if (breakevenAtRr > 0) {
    if (highWaterMark >= breakevenThreshold) {
      const steps = Math.floor((highWaterMark - breakevenThreshold) / trailingJump);
      targetStop = Math.max(targetStop, entryPrice + steps * trailingJump);
    }
  } else {
    const steps = Math.floor((highWaterMark - entryPrice) / trailingJump);
    if (steps > 0) {
      targetStop = Math.max(targetStop, initialStopPrice + steps * trailingJump);
    }
  }
  return Math.max(currentStopPrice, roundDownToTick(targetStop, tickSize));
}

/**
 * What an index option pays at expiry. NSE and BSE cash-settle index options at intrinsic value against the
 * underlying's closing value on expiry day; out of the money, the option expires at zero.
 */
export function expirySettlementPrice(optionType: 'CE' | 'PE', strike: number, underlyingClose: number): number {
  const intrinsic = optionType === 'CE' ? underlyingClose - strike : strike - underlyingClose;
  return Math.max(0, Math.round(intrinsic * 100) / 100);
}

/**
 * Statutory and broker charges for one option round trip (buy, then sell), as a percentage of premium unless named
 * in rupees. An estimate for the day book: the contract note is authoritative, and these rates change by budget
 * and exchange circular (STT on the options sell side rose from 0.10% to 0.15% on 2026-04-01).
 */
const BROKERAGE_PER_ORDER_INR = 20;
const STT_SELL_PCT = 0.15;
const EXCHANGE_TXN_PCT: Readonly<Record<string, number>> = { NSE_FNO: 0.03503, BSE_FNO: 0.0325 };
const SEBI_FEE_PCT = 0.0001;
const STAMP_DUTY_BUY_PCT = 0.003;
const GST_PCT = 18;

export function roundTripChargesInr(input: {
  quantity: number;
  buyPrice: number;
  sellPrice: number;
  exchangeSegment: string;
}): number {
  const buyPremium = input.quantity * input.buyPrice;
  const sellPremium = input.quantity * input.sellPrice;
  const turnover = buyPremium + sellPremium;
  const exchangeTxnPct = EXCHANGE_TXN_PCT[input.exchangeSegment] ?? EXCHANGE_TXN_PCT['NSE_FNO'] ?? 0;
  const brokerage = 2 * BROKERAGE_PER_ORDER_INR;
  const exchangeTxn = (turnover * exchangeTxnPct) / 100;
  const sebiFee = (turnover * SEBI_FEE_PCT) / 100;
  const stt = (sellPremium * STT_SELL_PCT) / 100;
  const stampDuty = (buyPremium * STAMP_DUTY_BUY_PCT) / 100;
  const gst = ((brokerage + exchangeTxn + sebiFee) * GST_PCT) / 100;
  return Number((brokerage + exchangeTxn + sebiFee + stt + stampDuty + gst).toFixed(2));
}
