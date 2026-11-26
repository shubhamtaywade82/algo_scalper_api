import type { OptionType } from '../domain/types.js';
import { istParts } from '../time/ist.js';

function sideKey(underlying: string, optionType?: OptionType): string {
  return optionType !== undefined ? `${underlying}:${optionType}` : underlying;
}

export interface DaySnapshot {
  readonly dayKey: string;
  readonly realizedPnlInr: number;
  readonly unrealizedPnlInr: number;
  readonly dayPnlInr: number;
  /** P&L relative to the session drawdown baseline (0 unless reset). */
  readonly effectiveDayPnlInr: number;
  /** Realized P&L relative to the session drawdown baseline. */
  readonly effectiveRealizedPnlInr: number;
  /** Session baseline against which drawdown is measured. */
  readonly dailyLossBaselineInr: number;
  /** Whether the daily loss brake is actively enforced. */
  readonly dailyLossBrakeEnabled: boolean;
  /** Loss if every open or pending position hits its stop. */
  readonly openRiskInr: number;
  readonly tradesToday: number;
  readonly openUnderlyings: readonly string[];
  readonly openPositions: number;
  readonly killSwitchReason: string | undefined;
  /** Set once the day has breached its loss limit. Latched separately from killSwitchReason, which an operator block can occupy first. */
  readonly dailyLossBreach: string | undefined;
}

/**
 * Book-wide state shared by every underlying: realised and unrealised day P&L,
 * entry count, per-underlying cooldown and the kill switch. The kill switch
 * persists across IST day rollovers and clears only through an explicit operator
 * action, so a daily-loss breach cannot silently re-arm itself.
 */
export class DayBook {
  private dayKey: string;
  private realized = 0;
  private trades = 0;
  private pnlBaseline = 0;
  private brakeEnabled = true;
  private readonly openPnl = new Map<string, number>();
  private readonly openRisk = new Map<string, number>();
  private readonly openSides = new Set<string>();
  private readonly cooldownUntil = new Map<string, number>();
  private killSwitchReason: string | undefined;
  private dailyLossBreach: string | undefined;

  constructor(
    nowMs: number,
    private readonly cooldownMs: number,
    brakeEnabled = true,
  ) {
    this.dayKey = istParts(nowMs).date;
    this.brakeEnabled = brakeEnabled;
  }

  /** Resets per-day counters when the IST date changes. Idempotent within a day. */
  observe(nowMs: number): void {
    const dayKey = istParts(nowMs).date;
    if (dayKey === this.dayKey) {
      return;
    }
    this.dayKey = dayKey;
    this.realized = 0;
    this.trades = 0;
    this.pnlBaseline = 0;
    this.cooldownUntil.clear();
  }

  recordEntry(underlying: string, optionType?: OptionType): void {
    this.trades += 1;
    this.openSides.add(sideKey(underlying, optionType));
  }

  /** Marks an underlying or side as holding (or having a pending) position without counting an entry. */
  markOpen(underlying: string, optionType?: OptionType): void {
    this.openSides.add(sideKey(underlying, optionType));
  }

  setOpenPnl(underlying: string, pnlInr: number, optionType?: OptionType): void {
    this.openPnl.set(sideKey(underlying, optionType), pnlInr);
  }

  /** What this side loses at its stop. Set when the entry is sent, and again from the fill. */
  setOpenRisk(underlying: string, riskInr: number, optionType?: OptionType): void {
    this.openRisk.set(sideKey(underlying, optionType), Math.max(0, riskInr));
  }

  recordClose(input: { underlying: string; optionType?: OptionType; pnlInr: number; closedAtMs: number }): void {
    this.realized += input.pnlInr;
    const key = sideKey(input.underlying, input.optionType);
    this.openSides.delete(key);
    this.openPnl.delete(key);
    this.openRisk.delete(key);
    if (this.cooldownMs > 0) {
      this.cooldownUntil.set(input.underlying, input.closedAtMs + this.cooldownMs);
    }
  }

  /** Releases an underlying or side whose entry never reached the market (rejected or not filled). */
  releaseUnfilled(underlying: string, optionType?: OptionType): void {
    const key = sideKey(underlying, optionType);
    this.openSides.delete(key);
    this.openPnl.delete(key);
    this.openRisk.delete(key);
  }

  isSideOpen(underlying: string, optionType: OptionType): boolean {
    return this.openSides.has(`${underlying}:${optionType}`) || this.openSides.has(underlying);
  }

  underlyingOpenPositions(underlying: string): number {
    let count = 0;
    for (const key of this.openSides) {
      if (key === underlying || key.startsWith(`${underlying}:`)) {
        count += 1;
      }
    }
    return count;
  }

  sideOpenPositions(optionType: OptionType): number {
    let count = 0;
    for (const key of this.openSides) {
      if (key.endsWith(`:${optionType}`)) {
        count += 1;
      }
    }
    return count;
  }

  activateKillSwitch(reason: string): void {
    this.killSwitchReason ??= reason;
  }

  /**
   * Records a daily-loss breach. The first breach reason is kept. The kill switch is set only if
   * nothing else holds it, so an operator block keeps its own reason and the breach is still latched.
   */
  recordDailyLossBreach(reason: string): void {
    this.dailyLossBreach ??= reason;
    this.activateKillSwitch(reason);
  }

  /** Operator action only. Clears the kill switch and the breach latch after the cause has been dealt with. */
  clearKillSwitch(): void {
    this.killSwitchReason = undefined;
    this.dailyLossBreach = undefined;
  }

  /** Absorbs current P&L as the session baseline, re-arming a fresh daily loss budget. */
  resetDrawdownBaseline(): number {
    this.pnlBaseline = this.realized;
    this.clearKillSwitch();
    return this.pnlBaseline;
  }

  setDrawdownBaseline(baselineInr: number): void {
    this.pnlBaseline = baselineInr;
  }

  setDailyLossBrake(enabled: boolean): void {
    this.brakeEnabled = enabled;
  }

  isDailyLossBrakeEnabled(): boolean {
    return this.brakeEnabled;
  }

  cooldownUntilFor(underlying: string): number | undefined {
    return this.cooldownUntil.get(underlying);
  }

  snapshot(): DaySnapshot {
    let unrealized = 0;
    for (const value of this.openPnl.values()) {
      unrealized += value;
    }
    let openRiskInr = 0;
    for (const value of this.openRisk.values()) {
      openRiskInr += value;
    }
    const underlyings = new Set<string>();
    for (const key of this.openSides) {
      const parts = key.split(':');
      const symbol = parts[0];
      if (symbol !== undefined) {
        underlyings.add(symbol);
      }
    }
    return {
      dayKey: this.dayKey,
      realizedPnlInr: this.realized,
      unrealizedPnlInr: unrealized,
      dayPnlInr: this.realized + unrealized,
      effectiveDayPnlInr: this.realized + unrealized - this.pnlBaseline,
      effectiveRealizedPnlInr: this.realized - this.pnlBaseline,
      dailyLossBaselineInr: this.pnlBaseline,
      dailyLossBrakeEnabled: this.brakeEnabled,
      openRiskInr,
      tradesToday: this.trades,
      openUnderlyings: [...underlyings].sort(),
      openPositions: this.openSides.size,
      killSwitchReason: this.killSwitchReason,
      dailyLossBreach: this.dailyLossBreach,
    };
  }
}
