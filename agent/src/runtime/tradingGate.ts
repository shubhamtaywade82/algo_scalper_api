/**
 * Process-level conditions under which the agent must not reach the broker. The agent consults this
 * before every order. Returning a reason blocks the order and names the cause for the operator.
 */
export interface TradingGate {
  /** A reason blocks new entries, or undefined when entries may proceed. */
  entryBlock(): string | undefined;
  /** A reason blocks exit orders, or undefined when exits may proceed. Only fail-stop conditions block exits. */
  exitBlock(): string | undefined;
}

export const OPEN_GATE: TradingGate = {
  entryBlock: () => undefined,
  exitBlock: () => undefined,
};

/**
 * Entries wait while any event is not yet confirmed in the journal and ledger, so the next trading decision
 * is made on a ledger that has every earlier event. Exits are not held back by the ledger: an exit reduces risk.
 * A lost lease stops entries only. An open position can be left with no exit if exits wait on the lease, and a
 * position with no working exit is the larger risk, so exits proceed. The exit path still reads the broker position
 * before it sends anything (see liveExecution.submitExit), so an exit cannot oversell a position another run closed.
 */
export function ledgerAndLeaseGate(input: {
  readonly unconfirmedEvents: () => number;
  readonly leaseHolds: () => boolean;
}): TradingGate {
  return {
    entryBlock: () => {
      if (!input.leaseHolds()) {
        return 'trading lease lost; another run may be trading this account';
      }
      const behind = input.unconfirmedEvents();
      return behind > 0 ? `${behind} event(s) are not yet confirmed in the journal and ledger; entries wait` : undefined;
    },
    exitBlock: () => undefined,
  };
}
