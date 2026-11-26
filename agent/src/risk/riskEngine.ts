export type RiskCode =
  | 'NOT_A_BUY_ORDER'
  | 'KILL_SWITCH_ACTIVE'
  | 'DAILY_LOSS_LIMIT'
  | 'DAILY_LOSS_AT_RISK'
  | 'TRADE_COUNT_LIMIT'
  | 'OPEN_POSITION_LIMIT'
  | 'UNDERLYING_ALREADY_OPEN'
  | 'UNDERLYING_SIDE_ALREADY_OPEN'
  | 'UNDERLYING_POSITION_LIMIT'
  | 'SIDE_POSITION_LIMIT'
  | 'OPPOSING_SIDE_OPEN'
  | 'COOLDOWN_ACTIVE'
  | 'OUTSIDE_ENTRY_WINDOW'
  | 'EXPIRY_DAY_CUTOFF'
  | 'SPOT_DATA_STALE'
  | 'OPTION_QUOTE_STALE'
  | 'PREMIUM_INVALID'
  | 'STOP_LOSS_INVALID'
  | 'TARGET_INVALID'
  | 'LOTS_OUT_OF_RANGE'
  | 'RISK_EXCEEDS_BUDGET'
  | 'INSUFFICIENT_FUNDS';

export interface PreTradeInput {
  readonly side: 'BUY' | 'SELL';
  readonly entryReference: number;
  readonly stopLossPrice: number;
  readonly targetPrice: number;
  readonly lots: number;
  readonly lotSize: number;
  readonly maxLotsPerOrder: number;
  readonly maxRiskInr: number;
  /**
   * All-in adverse loss of this order: charges and stop slippage on top of the planned stop distance (OTA-311). Always
   * supplied, so the shadow comparison can run. It decides only when `budgetBasis` is ALL_IN.
   */
  readonly allInRiskInr?: number;
  /** Which risk the budget and daily-loss checks use. PLANNED unless the policy is 'enforce'. */
  readonly budgetBasis?: 'PLANNED' | 'ALL_IN';
  readonly availableFundsInr: number;

  readonly nowMs: number;
  readonly minuteOfDay: number;
  readonly entryStartMinute: number;
  readonly entryEndMinute: number;
  readonly isExpiryDay: boolean;
  readonly expiryDayCutoffMinute: number;

  readonly killSwitchActive: boolean;
  readonly dailyPnlInr: number;
  readonly dailyLossLimitInr: number;
  /** Whether the daily loss brake is actively enforced. True when omitted. */
  readonly enforceDailyLoss?: boolean;
  /** Realised P&L today, without marks: the open positions are counted at their stops instead. */
  readonly realizedPnlInr: number;
  /** What every open or pending position loses if its stop is hit, across all underlyings. */
  readonly openRiskInr: number;
  readonly tradesToday: number;
  readonly maxTradesPerDay: number;
  readonly openPositions: number;
  readonly maxOpenPositions: number;
  readonly underlyingOpen?: boolean;
  readonly sideOpen?: boolean;
  readonly underlyingOpenPositions?: number;
  readonly maxPositionsPerUnderlying?: number;
  readonly sideOpenPositions?: number;
  readonly maxPositionsPerSide?: number;
  /** Open or pending positions on the other option type, across all underlyings. */
  readonly opposingSideOpenPositions?: number;
  /** Whether a CE and a PE may be open together. True when omitted. Set false to treat correlated indices as one risk unit. */
  readonly allowOpposingSides?: boolean;
  readonly cooldownUntilMs: number | undefined;

  /** Age of the latest spot tick; undefined when no tick has ever arrived. */
  readonly spotTickAgeMs: number | undefined;
  readonly optionQuoteAgeMs: number | undefined;
  readonly staleMs: number;
}

export interface RiskViolation {
  readonly code: RiskCode;
  readonly detail: string;
}

export interface RiskVerdict {
  readonly approved: boolean;
  readonly violations: readonly RiskViolation[];
  /** Risk recomputed from the order's own numbers, not from the sizing step. */
  readonly riskInr: number;
  /** The all-in adverse loss the gate was given, when there was one. */
  readonly allInRiskInr?: number;
}

type AddViolation = (code: RiskCode, detail: string) => void;

function checkAccountLimits(input: PreTradeInput, add: AddViolation): void {
  if (input.killSwitchActive) {
    add('KILL_SWITCH_ACTIVE', 'kill switch is active; no new entries');
  }
  if (input.enforceDailyLoss !== false && input.dailyLossLimitInr > 0 && input.dailyPnlInr <= -input.dailyLossLimitInr) {
    add('DAILY_LOSS_LIMIT', `day P&L ${input.dailyPnlInr.toFixed(2)} at or below -${input.dailyLossLimitInr.toFixed(2)}`);
  }
  if (input.maxTradesPerDay > 0 && input.tradesToday >= input.maxTradesPerDay) {
    add('TRADE_COUNT_LIMIT', `${input.tradesToday} entries today, limit ${input.maxTradesPerDay}`);
  }
}

function checkPositionLimits(input: PreTradeInput, add: AddViolation): void {
  if (input.openPositions >= input.maxOpenPositions) {
    add('OPEN_POSITION_LIMIT', `${input.openPositions} open, limit ${input.maxOpenPositions}`);
  }
  if (input.sideOpen === true) {
    add('UNDERLYING_SIDE_ALREADY_OPEN', 'this underlying already has an open position on this side');
  }
  if (input.underlyingOpen === true) {
    add('UNDERLYING_ALREADY_OPEN', 'this underlying already has an open position or pending entry');
  }
  if (input.maxPositionsPerUnderlying !== undefined && (input.underlyingOpenPositions ?? 0) >= input.maxPositionsPerUnderlying) {
    add('UNDERLYING_POSITION_LIMIT', `${input.underlyingOpenPositions ?? 0} open for underlying, limit ${input.maxPositionsPerUnderlying}`);
  }
  if (input.maxPositionsPerSide !== undefined && (input.sideOpenPositions ?? 0) >= input.maxPositionsPerSide) {
    add('SIDE_POSITION_LIMIT', `${input.sideOpenPositions ?? 0} open for side, limit ${input.maxPositionsPerSide}`);
  }
  if (input.allowOpposingSides === false && (input.opposingSideOpenPositions ?? 0) > 0) {
    add('OPPOSING_SIDE_OPEN', `${input.opposingSideOpenPositions} open on the opposite side; correlated indices are one risk unit`);
  }
}

function checkTimingLimits(input: PreTradeInput, add: AddViolation): void {
  if (input.cooldownUntilMs !== undefined && input.nowMs < input.cooldownUntilMs) {
    add('COOLDOWN_ACTIVE', `cooldown until ${new Date(input.cooldownUntilMs).toISOString()}`);
  }
  if (input.minuteOfDay < input.entryStartMinute || input.minuteOfDay >= input.entryEndMinute) {
    add('OUTSIDE_ENTRY_WINDOW', `minute ${input.minuteOfDay} outside [${input.entryStartMinute}, ${input.entryEndMinute})`);
  }
  if (input.isExpiryDay && input.minuteOfDay >= input.expiryDayCutoffMinute) {
    add('EXPIRY_DAY_CUTOFF', `expiry-day entries stop at minute ${input.expiryDayCutoffMinute}`);
  }
}

function checkDataFreshness(input: PreTradeInput, add: AddViolation): void {
  if (input.spotTickAgeMs === undefined || input.spotTickAgeMs > input.staleMs) {
    add('SPOT_DATA_STALE', `spot tick age ${input.spotTickAgeMs ?? 'unknown'} ms exceeds ${input.staleMs} ms`);
  }
  if (input.optionQuoteAgeMs === undefined || input.optionQuoteAgeMs > input.staleMs) {
    add('OPTION_QUOTE_STALE', `option quote age ${input.optionQuoteAgeMs ?? 'unknown'} ms exceeds ${input.staleMs} ms`);
  }
}

function checkOrderPricing(input: PreTradeInput, add: AddViolation): void {
  if (!(input.entryReference > 0) || !Number.isFinite(input.entryReference)) {
    add('PREMIUM_INVALID', `entry reference ${input.entryReference} is not a positive premium`);
  }
  if (!(input.stopLossPrice > 0) || !(input.stopLossPrice < input.entryReference)) {
    add('STOP_LOSS_INVALID', `stop ${input.stopLossPrice} must be positive and below entry ${input.entryReference}`);
  }
  if (!(input.targetPrice > input.entryReference)) {
    add('TARGET_INVALID', `target ${input.targetPrice} must be above entry ${input.entryReference}`);
  }
  if (!Number.isInteger(input.lots) || input.lots < 1 || input.lots > input.maxLotsPerOrder) {
    add('LOTS_OUT_OF_RANGE', `lots ${input.lots} outside [1, ${input.maxLotsPerOrder}]`);
  }
}

function checkOrderSizing(input: PreTradeInput, add: AddViolation): number {
  const riskInr = input.lots * input.lotSize * (input.entryReference - input.stopLossPrice);
  // The loss the account can take is never below the planned stop distance, so the budget uses the larger of the two (OTA-311).
  const budgetRiskInr = input.budgetBasis === 'ALL_IN' ? Math.max(riskInr, input.allInRiskInr ?? riskInr) : riskInr;
  if (budgetRiskInr > input.maxRiskInr) {
    const basis = budgetRiskInr === riskInr ? '' : ` (all-in; planned ${riskInr.toFixed(2)})`;
    add('RISK_EXCEEDS_BUDGET', `risk ${budgetRiskInr.toFixed(2)}${basis} exceeds budget ${input.maxRiskInr.toFixed(2)}`);
  }
  // Several open positions could together breach the daily loss limit if all hit stops.
  if (input.enforceDailyLoss !== false && input.dailyLossLimitInr > 0) {
    const worstCaseDayPnl = input.realizedPnlInr - input.openRiskInr - budgetRiskInr;
    if (worstCaseDayPnl < -input.dailyLossLimitInr) {
      add(
        'DAILY_LOSS_AT_RISK',
        `if every open stop and this one hit, day P&L would be ${worstCaseDayPnl.toFixed(2)}, beyond -${input.dailyLossLimitInr.toFixed(2)}`,
      );
    }
  }
  const premiumInr = input.lots * input.lotSize * input.entryReference;
  if (premiumInr > input.availableFundsInr) {
    add('INSUFFICIENT_FUNDS', `premium ${premiumInr.toFixed(2)} exceeds available funds ${input.availableFundsInr.toFixed(2)}`);
  }
  return riskInr;
}

/**
 * Pre-trade gate. Pure: it reads only its input and returns every violation,
 * so a rejected trade is explained completely in the event log. Nothing here
 * can be bypassed by the LLM advisor or the strategy.
 */
export function evaluatePreTrade(input: PreTradeInput): RiskVerdict {
  const violations: RiskViolation[] = [];
  const add: AddViolation = (code, detail) => {
    violations.push({ code, detail });
  };

  if (input.side !== 'BUY') {
    add('NOT_A_BUY_ORDER', `entry side is ${input.side}; this agent only buys options`);
  }
  checkAccountLimits(input, add);
  checkPositionLimits(input, add);
  checkTimingLimits(input, add);
  checkDataFreshness(input, add);
  checkOrderPricing(input, add);
  const riskInr = checkOrderSizing(input, add);

  return {
    approved: violations.length === 0,
    violations,
    riskInr,
    ...(input.allInRiskInr === undefined ? {} : { allInRiskInr: input.allInRiskInr }),
  };
}

/** A decision under the rollout policy, with the all-in shadow alongside it (OTA-311). */
export interface PolicyVerdict extends RiskVerdict {
  /** Would the all-in budget have refused this order? Recorded in every mode, so enforcement can be judged before it is turned on. */
  readonly allInWouldReject: boolean;
  readonly allInViolationCodes: readonly RiskCode[];
}

/**
 * The gate under a rollout policy. 'enforce' decides on all-in risk. 'off' and 'shadow' decide on planned risk, exactly as
 * before, and the all-in verdict is computed alongside it and returned for the journal.
 */
export function evaluatePreTradeUnderPolicy(input: PreTradeInput, policy: 'off' | 'shadow' | 'enforce'): PolicyVerdict {
  const decided = evaluatePreTrade({ ...input, budgetBasis: policy === 'enforce' ? 'ALL_IN' : 'PLANNED' });
  const shadow = input.allInRiskInr === undefined ? undefined : evaluatePreTrade({ ...input, budgetBasis: 'ALL_IN' });
  return {
    ...decided,
    allInWouldReject: shadow !== undefined && !shadow.approved,
    allInViolationCodes: shadow?.violations.map((violation) => violation.code) ?? [],
  };
}
