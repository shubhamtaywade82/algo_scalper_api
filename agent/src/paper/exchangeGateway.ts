import type { GatewayOrder, GatewayOutcome, OrderGateway } from '../execution/orderGateway.js';
import type { Logger } from '../ops/logger.js';
import { PaperExchangeError, type PaperExchangeClient, type PaperOrder } from './exchangeClient.js';

/** How far back through the ledger a fill is searched. Each page is 100 entries, newest first. */
const LEDGER_PAGES = 20;

export interface PaperExchangeGatewayOptions {
  readonly logger: Logger;
}

/**
 * Sends agent orders to a running paper_exchange server.
 *
 * Each order is a market order with `execution_price` set to the premium the agent acts on. The server fills it inside
 * the POST, so the response is already settled. A fill price is not in the order response, so it is read from the
 * account's TRADE ledger entry for that order. An order that is not filled at once is cancelled, because a working
 * order would be a position the agent has not recorded.
 */
export class PaperExchangeGateway implements OrderGateway {
  constructor(
    private readonly client: PaperExchangeClient,
    private readonly options: PaperExchangeGatewayOptions,
  ) {}

  async place(order: GatewayOrder): Promise<GatewayOutcome> {
    let placed: PaperOrder;
    try {
      placed = await this.client.placeOrder({
        client_order_id: order.correlationId,
        symbol: order.contract.underlying,
        side: order.side.toLowerCase(),
        quantity: order.quantity,
        order_type: 'market',
        instrument_type: 'OPTIDX',
        option_type: order.contract.optionType,
        strike_price: order.contract.strike,
        expiry_date: order.contract.expiry,
        exchange_segment: order.contract.exchangeSegment,
        execution_price: order.referencePrice,
        // A sell can only reduce the position the agent opened, never open a short.
        reduce_only: order.side === 'SELL',
      });
    } catch (error) {
      return this.placementOutcome(error, order);
    }
    return this.settle(placed, order);
  }

  private async settle(placed: PaperOrder, order: GatewayOrder): Promise<GatewayOutcome> {
    if (placed.status === 'filled') {
      return this.fillOutcome(placed.id, order);
    }
    if (placed.status === 'partially_filled' || placed.status === 'open' || placed.status === 'pending') {
      // Not settled at the execution price. Cancel the rest, then read what did fill.
      let after: PaperOrder;
      try {
        after = await this.client.cancelOrder(placed.id);
      } catch (error) {
        // A cancel that conflicts with a fill that happened meanwhile is read back, not guessed at.
        if (error instanceof PaperExchangeError && error.status === 409) {
          after = await this.client.order(placed.id);
        } else {
          return { kind: 'UNCONFIRMED', reason: `paper_exchange order ${placed.id} is not settled and could not be cancelled` };
        }
      }
      if (after.filledQuantity > 0) {
        return this.fillOutcome(placed.id, order);
      }
      if (after.status === 'filled') {
        return this.fillOutcome(placed.id, order);
      }
      return { kind: 'REJECTED', reason: 'paper_exchange did not fill the order at the execution price' };
    }
    if (placed.status === 'unknown') {
      return { kind: 'UNCONFIRMED', reason: `paper_exchange returned an order status this agent does not know (order ${placed.id})` };
    }
    return { kind: 'REJECTED', reason: `paper_exchange order ${placed.status}` };
  }

  /**
   * The fill from this order's TRADE ledger entries, with charges netted in. The server debits a buy by premium plus
   * charges and credits a sell by premium less charges. The average price carries the same net, so the agent's P&L
   * equals the wallet's change. Unconfirmed when no trade is found.
   */
  private async fillOutcome(orderId: number, order: GatewayOrder): Promise<GatewayOutcome> {
    const trades = await this.tradesFor(orderId);
    const filled = trades.reduce((sum, trade) => sum + trade.quantity, 0);
    if (filled <= 0) {
      return { kind: 'UNCONFIRMED', reason: `paper_exchange reports order ${orderId} filled but no TRADE entry was found` };
    }
    const notional = trades.reduce((sum, trade) => sum + trade.quantity * trade.price, 0);
    const charges = trades.reduce((sum, trade) => sum + trade.charges, 0);
    const net = order.side === 'BUY' ? notional + charges : notional - charges;
    return { kind: 'FILLED', filledQuantity: filled, averagePrice: net / filled };
  }

  private async tradesFor(orderId: number): Promise<Array<{ quantity: number; price: number; charges: number }>> {
    const found: Array<{ quantity: number; price: number; charges: number }> = [];
    let cursor: string | undefined;
    for (let page = 0; page < LEDGER_PAGES; page += 1) {
      const { entries, nextCursor } = await this.client.ledgerPage(cursor);
      for (const entry of entries) {
        if (entry.eventType === 'TRADE' && Number(entry.payload['order_id']) === orderId) {
          found.push({
            quantity: Number(entry.payload['quantity']),
            price: Number(entry.payload['price']),
            charges: chargesOf(entry.payload['charges']),
          });
        }
      }
      if (found.length > 0 || nextCursor === undefined) {
        break;
      }
      cursor = nextCursor;
    }
    return found.filter((trade) => trade.quantity > 0 && trade.price > 0);
  }

  private placementOutcome(error: unknown, order: GatewayOrder): GatewayOutcome {
    if (error instanceof PaperExchangeError) {
      return error.failure === 'REJECTED'
        ? { kind: 'REJECTED', reason: error.message }
        : { kind: 'UNCONFIRMED', reason: error.message };
    }
    this.options.logger.error('paper_exchange placement failed unexpectedly', { correlationId: order.correlationId });
    return { kind: 'UNCONFIRMED', reason: 'paper_exchange placement failed unexpectedly' };
  }

  /** Open positions on the account. Any non-zero net quantity counts, because the account is shared with the server's other strategies. */
  async openPositionCount(): Promise<number> {
    return (await this.client.positions()).filter((position) => position.netQuantity !== 0).length;
  }
}

/** Total charges on a TRADE entry. The server stores them as a hash that includes `total`; a missing hash counts as none. */
function chargesOf(value: unknown): number {
  if (value === null || typeof value !== 'object') {
    return 0;
  }
  const total = Number((value as Record<string, unknown>)['total'] ?? 0);
  return Number.isFinite(total) && total > 0 ? total : 0;
}
