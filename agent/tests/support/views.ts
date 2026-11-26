import type { AgentView, CockpitSnapshot } from '../../src/runtime/views.js';
import { istEpoch, SESSION_DAY } from './fixtures.js';

export function agentView(overrides: Partial<AgentView> & Pick<AgentView, 'symbol'>): AgentView {
  const position = overrides.position;
  return {
    state: 'IDLE',
    halted: undefined,
    spot: 22_451.3,
    spotAgeMs: 420,
    bars: 312,
    lastBarTime: istEpoch(SESSION_DAY, '10:25'),
    indicators: {
      emaFast: 22_455.2,
      emaSlow: 22_430.8,
      supertrend: 'UP',
      supertrendLine: 22_401.1,
      orbHigh: 22_465,
      orbLow: 22_380,
      orbFormed: true,
    },
    lastSignal: undefined,
    lastDrop: undefined,
    lastCandidate: undefined,
    lastExit: undefined,
    position,
    positions: overrides.positions ?? (position !== undefined ? [position] : []),
    cooldownUntil: undefined,
    ...overrides,
  };
}

export function snapshot(overrides: Partial<CockpitSnapshot> = {}): CockpitSnapshot {
  return {
    at: istEpoch(SESSION_DAY, '10:30'),
    mode: 'paper',
    phase: 'RUNNING',
    phaseDetail: undefined,
    capitalInr: 300_000,
    initialCapitalInr: 300_000,
    currentBalanceInr: 300_000,
    availableBalanceInr: 300_000,
    allocatedBalanceInr: 0,
    realTimeBalanceInr: 300_000,
    riskBudgetInr: 3_000,
    dailyLossLimitInr: 3_000,
    maxTradesPerDay: 3,
    maxOpenPositions: 1,
    maxHoldMinutes: 20,
    staleMs: 5_000,
    contractMaxSpreadPct: 2,
    contractMinOpenInterest: 100_000,
    chainWatch: undefined,
    day: {
      dayKey: SESSION_DAY,
      realizedPnlInr: 0,
      unrealizedPnlInr: 0,
      dayPnlInr: 0,
      tradesToday: 0,
      openUnderlyings: [],
      openPositions: 0,
      killSwitchReason: undefined,
    },
    underlyings: [agentView({ symbol: 'NIFTY' }), agentView({ symbol: 'BANKNIFTY', spot: 48_120.5, state: 'HALTED', halted: 'entry unconfirmed (ENT-1): timeout' })],
    ...overrides,
  };
}
