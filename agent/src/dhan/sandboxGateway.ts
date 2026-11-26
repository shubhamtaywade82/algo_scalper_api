import type { DhanClient } from '@nemesis-oss/dhanhq-sdk';
import type { GatewayOrder, GatewayOutcome, OrderGateway } from '../execution/orderGateway.js';
import type { Logger } from '../ops/logger.js';
import { classifyPlacementError } from './liveExecution.js';

/** The sandbox operations this gateway needs. Positions and orders are served by the sandbox in hybrid mode. */
export type SandboxClient = Pick<DhanClient, 'orders' | 'positions'>;

/** Order states the sandbox reports once an order can no longer change. Anything else is still working. */
const TERMINAL_UNFILLED = new Set(['REJECTED', 'CANCELLED', 'EXPIRED']);

export interface SandboxGatewayOptions {
  readonly orderTimeoutMs: number;
  readonly pollIntervalMs: number;
  readonly logger: Logger;
  readonly now?: () => number;
  readonly sleep?: (ms: number) => Promise<void>;
}

/**
 * Sends agent orders to the Dhan sandbox as regular MARKET orders, and reads each one back until it settles.
 *
 * The sandbox serves no super orders and no WebSocket, so this gateway has to poll `orders.getById`. Super orders
 * are not used here: the SDK refuses them in sandbox before any request is sent (SandboxUnsupportedError). An order
 * that is still working at the deadline is cancelled, and a fill that cannot be confirmed is UNCONFIRMED, never FILLED.
 */
export class DhanSandboxGateway implements OrderGateway {
  private readonly now: () => number;
  private readonly sleep: (ms: number) => Promise<void>;

  constructor(
    private readonly client: SandboxClient,
    private readonly options: SandboxGatewayOptions,
  ) {
    this.now = options.now ?? Date.now;
    this.sleep = options.sleep ?? ((ms) => new Promise((resolve) => setTimeout(resolve, ms)));
  }

  async place(order: GatewayOrder): Promise<GatewayOutcome> {
    let orderId: string;
    try {
      const placed = await this.client.orders.place({
        correlationId: order.correlationId,
        transactionType: order.side,
        exchangeSegment: order.contract.exchangeSegment,
        productType: 'INTRADAY',
        orderType: 'MARKET',
        quantity: order.quantity,
        securityId: order.contract.securityId,
      });
      orderId = placed.data.orderId;
    } catch (error) {
      // A rejection proves the order never reached the matching engine. Anything else is ambiguous.
      const kind = classifyPlacementError(error);
      const reason = `sandbox refused the placement: ${describe(error)}`;
      return kind === 'REJECTED' ? { kind: 'REJECTED', reason } : { kind: 'UNCONFIRMED', reason };
    }

    const deadline = this.now() + this.options.orderTimeoutMs;
    for (;;) {
      const settled = await this.readSettled(orderId, order);
      if (settled !== undefined) {
        return settled;
      }
      if (this.now() >= deadline) {
        return this.cancelAtDeadline(orderId, order);
      }
      await this.sleep(this.options.pollIntervalMs);
    }
  }

  /** The order's outcome when the sandbox has settled it, or undefined while it is still working. Read errors are retried. */
  private async readSettled(orderId: string, order: GatewayOrder): Promise<GatewayOutcome | undefined> {
    let state;
    try {
      state = await this.client.orders.getById(orderId);
    } catch (error) {
      this.options.logger.warn('sandbox order read failed; retrying', { correlationId: order.correlationId, error: describe(error) });
      return undefined;
    }
    const status = state.orderStatus ?? '';
    const filled = Number(state.filledQty ?? 0);
    const average = Number(state.averageTradedPrice ?? 0);
    if (status === 'TRADED') {
      return fillOutcome(filled > 0 ? filled : order.quantity, average, order);
    }
    if (TERMINAL_UNFILLED.has(status)) {
      // A partial fill followed by a cancel still left a position at the venue, so it is reported as a fill.
      return filled > 0 ? fillOutcome(filled, average, order) : { kind: 'REJECTED', reason: `sandbox order ${status}` };
    }
    return undefined;
  }

  /** At the deadline the remainder is cancelled. The order is read again, because a cancel can race a fill. */
  private async cancelAtDeadline(orderId: string, order: GatewayOrder): Promise<GatewayOutcome> {
    try {
      await this.client.orders.cancel(orderId);
    } catch (error) {
      this.options.logger.warn('sandbox cancel at deadline failed', { correlationId: order.correlationId, error: describe(error) });
    }
    const settled = await this.readSettled(orderId, order);
    return settled ?? { kind: 'UNCONFIRMED', reason: 'sandbox order was still working at the deadline and could not be read' };
  }

  /** Open option positions in the sandbox account. Non-zero net quantity on an F&O segment. */
  async openPositionCount(): Promise<number> {
    const rows = await this.client.positions.list();
    return rows.filter(
      (row) =>
        (String(row.exchangeSegment) === 'NSE_FNO' || String(row.exchangeSegment) === 'BSE_FNO') && (row.netQty ?? 0) !== 0,
    ).length;
  }
}

function fillOutcome(filledQuantity: number, averagePrice: number, order: GatewayOrder): GatewayOutcome {
  if (!(averagePrice > 0)) {
    return { kind: 'UNCONFIRMED', reason: `sandbox reports ${filledQuantity} filled for ${order.correlationId} without an average price` };
  }
  return { kind: 'FILLED', filledQuantity, averagePrice };
}

function describe(error: unknown): string {
  return error instanceof Error ? `${error.name}: ${error.message}`.slice(0, 240) : String(error).slice(0, 240);
}
