import type { Direction } from '../domain/types.js';
import type { ReplayTrade } from './replay.js';

/** The account-wide limits live trading applies across underlyings. Single-index replays cannot see them. */
export interface PortfolioRules {
  readonly dailyLossLimitInr: number;
  readonly maxPositionsPerSide: number;
  readonly maxOpenPositions: number;
}

export interface PortfolioTrade extends ReplayTrade {
  readonly underlying: string;
}

export interface PortfolioResult {
  readonly taken: readonly PortfolioTrade[];
  readonly skipped: Readonly<Record<'DAILY_LOSS' | 'PER_SIDE' | 'OPEN_POSITIONS' | 'UNDERLYING_BUSY', number>>;
}

/**
 * Replays the account-wide gates over trades that single-index replays produced with no daily limit. Trades are
 * taken in entry order; one that a live gate would refuse is skipped. Approximation: a skipped trade cannot free
 * its index for a different entry, because the single-index replay never generated one.
 */
export function simulatePortfolio(trades: readonly PortfolioTrade[], rules: PortfolioRules): PortfolioResult {
  const taken: PortfolioTrade[] = [];
  const skipped = { DAILY_LOSS: 0, PER_SIDE: 0, OPEN_POSITIONS: 0, UNDERLYING_BUSY: 0 };
  const byDay = new Map<string, PortfolioTrade[]>();
  for (const trade of [...trades].sort((a, b) => a.entryTime - b.entryTime)) {
    byDay.set(trade.date, [...(byDay.get(trade.date) ?? []), trade]);
  }
  for (const dayTrades of byDay.values()) {
    let realizedInr = 0;
    let open: PortfolioTrade[] = [];
    for (const trade of dayTrades) {
      realizedInr += open.filter((held) => held.exitTime <= trade.entryTime).reduce((total, held) => total + held.netPnlInr, 0);
      open = open.filter((held) => held.exitTime > trade.entryTime);
      const refusal = refusalFor(trade, open, realizedInr, rules);
      if (refusal !== undefined) {
        skipped[refusal] += 1;
        continue;
      }
      open.push(trade);
      taken.push(trade);
    }
  }
  return { taken, skipped };
}

function refusalFor(trade: PortfolioTrade, open: readonly PortfolioTrade[], realizedInr: number, rules: PortfolioRules): keyof PortfolioResult['skipped'] | undefined {
  const openRiskInr = open.reduce((total, held) => total + held.riskInr, 0);
  if (realizedInr <= -rules.dailyLossLimitInr || realizedInr - openRiskInr - trade.riskInr < -rules.dailyLossLimitInr) {
    return 'DAILY_LOSS';
  }
  if (open.some((held) => held.underlying === trade.underlying)) {
    return 'UNDERLYING_BUSY';
  }
  if (open.length >= rules.maxOpenPositions) {
    return 'OPEN_POSITIONS';
  }
  const sameSide = (direction: Direction): number => open.filter((held) => held.direction === direction).length;
  return sameSide(trade.direction) >= rules.maxPositionsPerSide ? 'PER_SIDE' : undefined;
}
