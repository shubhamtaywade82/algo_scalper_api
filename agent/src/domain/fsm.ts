/**
 * Deterministic per-underlying trade lifecycle. Every legal transition is in
 * TRANSITIONS; any other (state, event) pair throws. Ambiguous outcomes (an
 * order whose fate is unknown, a reconciliation mismatch) move to HALTED, which
 * blocks all activity until an operator reconciles and issues RESET.
 */
export const TRADE_STATES = [
  'IDLE',
  'SIGNAL_DETECTED',
  'ENTRY_PENDING',
  'POSITION_OPEN',
  'RISK_MANAGEMENT_ACTIVE',
  'EXIT_PENDING',
  'POSITION_CLOSED',
  'HALTED',
] as const;

export type TradeState = (typeof TRADE_STATES)[number];

export const TRADE_EVENTS = [
  'SIGNAL_FOUND',
  'SIGNAL_DROPPED',
  'ENTRY_SUBMITTED',
  'ENTRY_FILLED',
  'ENTRY_REJECTED',
  'ENTRY_UNCONFIRMED',
  'PROTECTION_ARMED',
  'EXIT_SUBMITTED',
  'EXIT_FILLED',
  'EXIT_REJECTED',
  'EXIT_UNCONFIRMED',
  'PROTECTIVE_EXIT_FILLED',
  'CLOSE_ACKNOWLEDGED',
  'HALT',
  'RESET',
] as const;

export type TradeEvent = (typeof TRADE_EVENTS)[number];

type TransitionTable = { readonly [S in TradeState]: { readonly [E in TradeEvent]?: TradeState } };

export const TRANSITIONS: TransitionTable = {
  IDLE: {
    SIGNAL_FOUND: 'SIGNAL_DETECTED',
    HALT: 'HALTED',
  },
  SIGNAL_DETECTED: {
    SIGNAL_DROPPED: 'IDLE',
    ENTRY_SUBMITTED: 'ENTRY_PENDING',
    HALT: 'HALTED',
  },
  ENTRY_PENDING: {
    ENTRY_FILLED: 'POSITION_OPEN',
    ENTRY_REJECTED: 'IDLE',
    ENTRY_UNCONFIRMED: 'HALTED',
    HALT: 'HALTED',
  },
  POSITION_OPEN: {
    PROTECTION_ARMED: 'RISK_MANAGEMENT_ACTIVE',
    EXIT_SUBMITTED: 'EXIT_PENDING',
    PROTECTIVE_EXIT_FILLED: 'POSITION_CLOSED',
    HALT: 'HALTED',
  },
  RISK_MANAGEMENT_ACTIVE: {
    EXIT_SUBMITTED: 'EXIT_PENDING',
    PROTECTIVE_EXIT_FILLED: 'POSITION_CLOSED',
    HALT: 'HALTED',
  },
  EXIT_PENDING: {
    EXIT_FILLED: 'POSITION_CLOSED',
    PROTECTIVE_EXIT_FILLED: 'POSITION_CLOSED',
    EXIT_REJECTED: 'RISK_MANAGEMENT_ACTIVE',
    EXIT_UNCONFIRMED: 'HALTED',
    HALT: 'HALTED',
  },
  POSITION_CLOSED: {
    CLOSE_ACKNOWLEDGED: 'IDLE',
    HALT: 'HALTED',
  },
  HALTED: {
    RESET: 'IDLE',
  },
};

export class IllegalTransitionError extends Error {
  constructor(
    readonly from: TradeState,
    readonly event: TradeEvent,
  ) {
    super(`illegal trade transition: ${from} --${event}-->`);
    this.name = 'IllegalTransitionError';
  }
}

export interface TransitionRecord {
  readonly from: TradeState;
  readonly event: TradeEvent;
  readonly to: TradeState;
  readonly at: number;
}

export class TradeStateMachine {
  private current: TradeState = 'IDLE';
  private readonly records: TransitionRecord[] = [];

  constructor(
    private readonly now: () => number = Date.now,
    private readonly maxHistory = 200,
  ) {}

  get state(): TradeState {
    return this.current;
  }

  can(event: TradeEvent): boolean {
    return TRANSITIONS[this.current][event] !== undefined;
  }

  dispatch(event: TradeEvent): TradeState {
    const next = TRANSITIONS[this.current][event];
    if (next === undefined) {
      throw new IllegalTransitionError(this.current, event);
    }
    this.records.push({ from: this.current, event, to: next, at: this.now() });
    if (this.records.length > this.maxHistory) {
      this.records.shift();
    }
    this.current = next;
    return next;
  }

  /** Transitions directly to an active state when adopting a durable open position on restart. */
  adopt(state: TradeState): void {
    this.records.push({ from: this.current, event: 'RESET', to: state, at: this.now() });
    this.current = state;
  }

  history(): readonly TransitionRecord[] {
    return this.records;
  }
}
