import type { TradingMode } from '../domain/mode.js';
import type { TradeState } from '../domain/fsm.js';
import type { Direction, ExitReason, OptionType } from '../domain/types.js';
import type { ChainAnalysis } from '../options/chainAnalyzer.js';
import type { MarketContext } from '../strategy/marketContext.js';

/**
 * Read-only views the operator cockpit renders. They are plain data: building one
 * never changes trading state, and rendering one never calls back into the agent.
 */

export interface SignalView {
  readonly direction: Direction;
  readonly barTime: number;
  readonly spot: number;
  readonly reasons: readonly string[];
  readonly at: number;
}

export interface DropView {
  readonly code: string;
  readonly detail: string;
  readonly at: number;
}

export interface CandidateView {
  readonly contractSymbol: string;
  readonly optionType: OptionType;
  readonly strike: number;
  readonly expiry: string;
  readonly entryReference: number;
  readonly bid: number;
  readonly spreadPct: number;
  readonly openInterest: number;
  readonly lots: number;
  readonly quantity: number;
  readonly stopLossPrice: number;
  readonly targetPrice: number;
  readonly riskInr: number;
  readonly at: number;
}

export interface ExitView {
  readonly reason: ExitReason;
  readonly pnlInr: number;
  readonly at: number;
}

export interface PositionView {
  readonly contractSymbol: string;
  readonly optionType: OptionType;
  readonly strike: number;
  readonly expiry: string;
  readonly quantity: number;
  readonly averagePrice: number;
  readonly stopLossPrice: number;
  readonly targetPrice: number;
  readonly mark: number | undefined;
  readonly unrealizedInr: number | undefined;
  readonly openedAt: number;
  readonly heldMinutes: number;
  readonly exitRequested: boolean;
  /** Where the stop and target are held: at the broker, or by the agent. Absent on views from older snapshots. */
  readonly protection?: 'EXCHANGE_BRACKET' | 'CLIENT_SIDE';
}

export interface IndicatorView {
  readonly emaFast: number | undefined;
  readonly emaSlow: number | undefined;
  readonly supertrend: 'UP' | 'DOWN' | undefined;
  readonly supertrendLine: number | undefined;
  readonly orbHigh: number | undefined;
  readonly orbLow: number | undefined;
  readonly orbFormed: boolean;
}

export interface FeedStatusView {
  readonly status: 'connected' | 'connecting' | 'disconnected' | 'reconnecting';
  readonly subscribedCount: number;
  readonly totalTicks: number;
  readonly lastTickAt?: number | undefined;
  readonly disconnectReason?: number | string | undefined;
}

export interface ChainWatchLegView {
  readonly bid: number | undefined;
  readonly ask: number | undefined;
  readonly spreadPct: number | undefined;
  readonly openInterest: number | undefined;
  readonly passesGate: boolean;
}

export interface ChainWatchRowView {
  readonly strike: number;
  readonly markers: readonly ('ATM' | 'CE_ENTRY' | 'PE_ENTRY' | 'OPEN' | 'RES' | 'SUP')[];
  readonly call: ChainWatchLegView;
  readonly put: ChainWatchLegView;
}

/** ST + EMA agree → single-sided chain lens; otherwise both columns. */
export type ChainMarketBias = 'BULLISH' | 'BEARISH' | 'NEUTRAL';

export interface ChainWatchView {
  readonly symbol: string;
  readonly spot: number | undefined;
  readonly expiry: string | undefined;
  readonly atmStrike: number | undefined;
  readonly bullishEntryStrike: number | undefined;
  readonly bearishEntryStrike: number | undefined;
  readonly fetchedAgeMs: number | undefined;
  readonly status: 'idle' | 'loading' | 'waiting_spot' | 'ready' | 'error';
  readonly error: string | undefined;
  readonly rows: readonly ChainWatchRowView[];
  readonly maxOpenInterest: number;
  readonly strikeScroll: number;
  readonly strikeScrollMin: number;
  readonly strikeScrollMax: number;
  readonly marketBias: ChainMarketBias;
  readonly analysis?: ChainAnalysis | undefined;
}

export interface AgentView {
  readonly symbol: string;
  readonly state: TradeState;
  readonly halted: string | undefined;
  readonly spot: number | undefined;
  readonly spotAgeMs: number | undefined;
  readonly bars: number;
  readonly lastBarTime: number | undefined;
  readonly indicators: IndicatorView;
  readonly lastSignal: SignalView | undefined;
  readonly lastDrop: DropView | undefined;
  readonly lastCandidate: CandidateView | undefined;
  readonly lastExit: ExitView | undefined;
  readonly position: PositionView | undefined;
  readonly positions: readonly PositionView[];
  readonly cooldownUntil: number | undefined;
  /** Day trend, regime and market structure as of the last closed bar. */
  readonly context?: MarketContext | undefined;
}

export interface CockpitSnapshot {
  readonly at: number;
  readonly mode: TradingMode;
  readonly phase: 'IDLE' | 'STARTING' | 'RUNNING' | 'STOPPING' | 'STOPPED' | 'FAILED';
  readonly phaseDetail: string | undefined;
  readonly capitalInr: number;
  readonly initialCapitalInr: number;
  readonly currentBalanceInr: number;
  readonly availableBalanceInr: number;
  readonly allocatedBalanceInr: number;
  readonly realTimeBalanceInr: number;
  readonly riskBudgetInr: number;
  readonly dailyLossLimitInr: number;
  /** Best day P&L seen by this run (restored from realised P&L on restart). */
  readonly dayPeakPnlInr?: number;
  readonly maxTradesPerDay: number;
  readonly maxOpenPositions: number;
  readonly maxHoldMinutes: number;
  readonly staleMs: number;
  readonly contractMaxSpreadPct: number;
  readonly contractMinOpenInterest: number;
  readonly entryStartMinute?: number;
  readonly entryEndMinute?: number;
  readonly day: {
    readonly dayKey: string;
    readonly realizedPnlInr: number;
    readonly unrealizedPnlInr: number;
    readonly dayPnlInr: number;
    readonly effectiveDayPnlInr?: number;
    readonly effectiveRealizedPnlInr?: number;
    readonly dailyLossBaselineInr?: number;
    readonly dailyLossBrakeEnabled?: boolean;
    readonly tradesToday: number;
    readonly openUnderlyings: readonly string[];
    readonly openPositions: number;
    readonly killSwitchReason: string | undefined;
  };
  readonly underlyings: readonly AgentView[];
  /** ATM ladder for the cockpit-selected underlying; other underlyings are not fetched. */
  readonly chainWatch: ChainWatchView | undefined;
  /** Active session posture and enabled strategies. */
  readonly strategy?: StrategySessionView;
  /** Live WebSocket feed status and metrics. */
  readonly feed?: FeedStatusView | undefined;
}

export interface StrategyChoiceView {
  readonly id: string;
  readonly label: string;
  readonly on: boolean;
}

export interface StrategySessionView {
  readonly posture: string;
  readonly strategies: readonly StrategyChoiceView[];
}

