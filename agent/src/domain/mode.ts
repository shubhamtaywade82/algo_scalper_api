/**
 * The three ways the agent runs. Market data is always the real Dhan feed in every mode. Only the venue differs.
 *
 * - live: real market data, real order execution on the production Dhan account.
 * - sandbox: real market data, orders sent to the Dhan sandbox with sandbox credentials and base URL.
 * - paper: real market data, orders simulated locally and persisted in PostgreSQL (wallet, orders, positions, P&L).
 */
export type TradingMode = 'live' | 'sandbox' | 'paper';

export const TRADING_MODES: readonly TradingMode[] = ['live', 'sandbox', 'paper'];

/** Modes whose orders reach a Dhan account (sandbox or production). These read the broker's books at start. */
export function sendsOrdersToDhan(mode: TradingMode): boolean {
  return mode === 'live' || mode === 'sandbox';
}
