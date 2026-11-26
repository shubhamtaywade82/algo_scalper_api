import type { ExitReason, OptionContract } from '../domain/types.js';

/**
 * One order as a venue gateway receives it. Every order here is a MARKET order on a long option: entries buy,
 * exits and protective exits sell. `referencePrice` is the premium the agent is acting on. Venues that price from
 * a supplied price (paper_exchange) fill at it; venues that price themselves (Dhan) ignore it.
 */
export interface GatewayOrder {
  /** Unique per attempt. The venue uses it as its idempotency key. */
  readonly correlationId: string;
  readonly side: 'BUY' | 'SELL';
  readonly contract: OptionContract;
  readonly quantity: number;
  readonly referencePrice: number;
  /** Set on protective exits, so the venue record says why it was sold. */
  readonly reason: ExitReason | undefined;
}

/**
 * The venue's answer for one order. A gateway returns only a settled answer. `UNCONFIRMED` means the venue may or may
 * not have filled the order, so the agent halts rather than guess. Never report a fill the venue did not confirm.
 */
export type GatewayOutcome =
  | { readonly kind: 'FILLED'; readonly filledQuantity: number; readonly averagePrice: number }
  | { readonly kind: 'REJECTED'; readonly reason: string }
  | { readonly kind: 'UNCONFIRMED'; readonly reason: string };

/**
 * A venue that takes market orders and reports settled outcomes. Implemented by the Dhan sandbox and by the
 * paper_exchange server. Both have no exchange-held bracket, so stops and targets are enforced by the port.
 */
export interface OrderGateway {
  place(order: GatewayOrder): Promise<GatewayOutcome>;
  /** Open option positions the venue holds for the account. The orchestrator refuses to start while this is non-zero. */
  openPositionCount(): Promise<number>;
}
