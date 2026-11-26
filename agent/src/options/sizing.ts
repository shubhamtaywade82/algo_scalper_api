export interface SizingInput {
  readonly capitalInr: number;
  readonly maxRiskPerTradePct: number;
  /** Cash available to pay the premium. Option buyers pay the full premium up front. */
  readonly availableFundsInr: number;
  /** Entry reference premium (the ask used for the market order). */
  readonly entryReference: number;
  readonly stopLossPrice: number;
  readonly lotSize: number;
  readonly maxLotsPerOrder: number;
  /**
   * All-in adverse loss of one lot (OTA-311). When given, lots are sized on it instead of the planned stop distance, so
   * the budget bounds what the account can lose. Charges are taken per lot, which is the conservative reading.
   */
  readonly perLotRiskInr?: number;
}

export interface SizingResult {
  readonly lots: number;
  readonly quantity: number;
  readonly riskBudgetInr: number;
  readonly riskInr: number;
  readonly premiumInr: number;
  readonly limitedBy: 'RISK' | 'FUNDS' | 'MAX_LOTS' | 'NONE';
}

/**
 * Whole-lot sizing against an explicit risk budget. Lots are floored, never
 * rounded up, so realised risk can only be at or below the budget. Zero lots is
 * a valid result meaning "this trade does not fit the budget".
 */
export function sizePosition(input: SizingInput): SizingResult {
  const riskBudgetInr = (input.capitalInr * input.maxRiskPerTradePct) / 100;
  const riskPerLotInr = input.perLotRiskInr ?? (input.entryReference - input.stopLossPrice) * input.lotSize;
  const premiumPerLotInr = input.entryReference * input.lotSize;

  if (!(riskPerLotInr > 0) || !(premiumPerLotInr > 0) || !Number.isFinite(riskPerLotInr)) {
    return { lots: 0, quantity: 0, riskBudgetInr, riskInr: 0, premiumInr: 0, limitedBy: 'RISK' };
  }

  const lotsByRisk = Math.floor(riskBudgetInr / riskPerLotInr);
  const lotsByFunds = Math.max(0, Math.floor(input.availableFundsInr / premiumPerLotInr));
  const lots = Math.min(lotsByRisk, lotsByFunds, input.maxLotsPerOrder);

  let limitedBy: SizingResult['limitedBy'] = 'NONE';
  if (lots === lotsByRisk && lotsByRisk <= lotsByFunds && lotsByRisk <= input.maxLotsPerOrder) {
    limitedBy = 'RISK';
  } else if (lots === lotsByFunds && lotsByFunds <= input.maxLotsPerOrder) {
    limitedBy = 'FUNDS';
  } else if (lots === input.maxLotsPerOrder) {
    limitedBy = 'MAX_LOTS';
  }

  return {
    lots,
    quantity: lots * input.lotSize,
    riskBudgetInr,
    riskInr: lots * riskPerLotInr,
    premiumInr: lots * premiumPerLotInr,
    limitedBy,
  };
}
