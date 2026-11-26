import type { ExitReason, Tick } from '../domain/types.js';
import type { Logger } from '../ops/logger.js';
import { calculateTrailingStop } from '../options/pricing.js';
import { correlationIdFor, fitsBrokerLimit } from './brokerIds.js';
import type { GatewayOrder, GatewayOutcome, OrderGateway } from './orderGateway.js';
import type { EntryOrder, ExecutionEvent, ExecutionListener, ExecutionPort, ExitOrder } from './ports.js';

interface OpenPosition {
  readonly positionId: string;
  readonly underlying: string;
  readonly contract: EntryOrder['contract'];
  readonly quantity: number;
  readonly averagePrice: number;
  readonly initialStopPrice: number;
  stopLossPrice: number;
  highWaterMark: number;
  readonly targetPrice: number;
  readonly trailingJump?: number | undefined;
  readonly breakevenAtRr?: number | undefined;
  readonly runner?: boolean | undefined;
  /** Set while a sell is in flight. Stop, target and agent exit cannot all sell the same position. */
  exiting: boolean;
}

export interface GatewayPortOptions {
  /** `sandbox` for the Dhan sandbox account, `paper` for the paper_exchange server. */
  readonly mode: 'sandbox' | 'paper';
  readonly logger: Logger;
  readonly now?: () => number;
}

/**
 * Execution over a venue that takes market orders and settles them, without an exchange-held bracket.
 *
 * The agent holds the stop and target. When the option's LTP reaches them, the port sends the sell itself. A process
 * that dies with a position open leaves that position without a stop. Live mode does not have this gap: its stop and
 * target are super-order legs held by the exchange. That difference is why this port is not used for live.
 *
 * Event rules, the same as the other venues:
 *  - An entry is FILLED only when the venue settled it as filled.
 *  - A sell that the venue cannot confirm is UNCONFIRMED: the position is kept, nothing is retried, and the agent halts.
 *  - A protective sell that is rejected leaves the position open at the venue, so it is a BROKER_MISMATCH and halts.
 */
export class GatewayExecutionPort implements ExecutionPort {
  readonly protection: 'EXCHANGE_BRACKET' | 'CLIENT_SIDE' = 'CLIENT_SIDE';
  readonly mode: 'sandbox' | 'paper';
  /** The paper gateway is paper_exchange, which nets charges into fill prices. The Dhan sandbox reports gross. */
  readonly chargesInFills: boolean;
  private readonly listeners = new Set<ExecutionListener>();
  private readonly positions = new Map<string, OpenPosition>();
  private readonly now: () => number;
  private protectiveSequence = 0;

  constructor(
    private readonly gateway: OrderGateway,
    private readonly options: GatewayPortOptions,
  ) {
    this.mode = options.mode;
    this.chargesInFills = options.mode === 'paper';
    this.now = options.now ?? Date.now;
  }

  onEvent(listener: ExecutionListener): () => void {
    this.listeners.add(listener);
    return () => {
      this.listeners.delete(listener);
    };
  }

  /** Open option positions at the venue. Used by the orchestrator's start check. */
  openPositionCount(): Promise<number> {
    return this.gateway.openPositionCount();
  }

  async submitEntry(order: EntryOrder): Promise<void> {
    const outcome = await this.send({
      correlationId: order.correlationId,
      side: 'BUY',
      contract: order.contract,
      quantity: order.quantity,
      referencePrice: order.entryReference,
      reason: undefined,
    });
    if (outcome.kind === 'REJECTED') {
      this.emit({ kind: 'ENTRY_REJECTED', correlationId: order.correlationId, underlying: order.underlying, reason: outcome.reason });
      return;
    }
    if (outcome.kind === 'UNCONFIRMED') {
      this.emit({ kind: 'ENTRY_UNCONFIRMED', correlationId: order.correlationId, underlying: order.underlying, reason: outcome.reason });
      return;
    }
    this.positions.set(order.correlationId, {
      positionId: order.correlationId,
      underlying: order.underlying,
      contract: order.contract,
      quantity: outcome.filledQuantity,
      averagePrice: outcome.averagePrice,
      initialStopPrice: order.stopLossPrice,
      stopLossPrice: order.stopLossPrice,
      highWaterMark: outcome.averagePrice,
      targetPrice: order.targetPrice,
      trailingJump: order.trailingJump,
      breakevenAtRr: order.breakevenAtRr,
      runner: order.runner,
      exiting: false,
    });
    this.emit({
      kind: 'ENTRY_FILLED',
      correlationId: order.correlationId,
      underlying: order.underlying,
      quantity: outcome.filledQuantity,
      averagePrice: outcome.averagePrice,
      at: this.now(),
    });
  }

  async submitExit(order: ExitOrder): Promise<void> {
    const position = this.positions.get(order.positionId);
    if (position === undefined) {
      this.emit({
        kind: 'EXIT_REJECTED',
        correlationId: order.correlationId,
        underlying: order.underlying,
        positionId: order.positionId,
        reason: 'no open position with this id',
      });
      return;
    }
    if (position.exiting) {
      this.emit({
        kind: 'EXIT_REJECTED',
        correlationId: order.correlationId,
        underlying: order.underlying,
        positionId: order.positionId,
        reason: 'an exit for this position is already in flight',
      });
      return;
    }
    if (order.quantity < position.quantity) {
      this.emit({
        kind: 'EXIT_REJECTED',
        correlationId: order.correlationId,
        underlying: order.underlying,
        positionId: order.positionId,
        reason: 'partial exits are not supported; the position closes whole',
      });
      return;
    }
    position.exiting = true;
    const outcome = await this.send({
      correlationId: order.correlationId,
      side: 'SELL',
      contract: position.contract,
      quantity: position.quantity,
      referencePrice: order.referencePrice,
      reason: order.reason,
    });
    if (outcome.kind === 'REJECTED') {
      position.exiting = false;
      this.emit({
        kind: 'EXIT_REJECTED',
        correlationId: order.correlationId,
        underlying: order.underlying,
        positionId: order.positionId,
        reason: outcome.reason,
      });
      return;
    }
    if (outcome.kind === 'UNCONFIRMED') {
      // The position stays marked exiting: a sell that may have filled must not be sent again.
      this.emit({
        kind: 'EXIT_UNCONFIRMED',
        correlationId: order.correlationId,
        underlying: order.underlying,
        positionId: order.positionId,
        reason: outcome.reason,
      });
      return;
    }
    this.positions.delete(order.positionId);
    this.emit({
      kind: 'EXIT_FILLED',
      correlationId: order.correlationId,
      underlying: order.underlying,
      positionId: order.positionId,
      quantity: outcome.filledQuantity,
      averagePrice: outcome.averagePrice,
      reason: order.reason,
      at: this.now(),
    });
  }

  /** Stop and target are enforced against the option's live LTP. The sell goes to the venue when either is reached. */
  onOptionTick(tick: Tick): void {
    for (const position of [...this.positions.values()]) {
      if (position.exiting || position.contract.securityId !== tick.securityId || position.contract.exchangeSegment !== tick.exchangeSegment) {
        continue;
      }
      if (position.trailingJump !== undefined && position.trailingJump > 0) {
        position.highWaterMark = Math.max(position.highWaterMark, tick.ltp);
        position.stopLossPrice = calculateTrailingStop({
          entryPrice: position.averagePrice,
          initialStopPrice: position.initialStopPrice,
          currentStopPrice: position.stopLossPrice,
          highWaterMark: position.highWaterMark,
          trailingJump: position.trailingJump,
          breakevenAtRr: position.breakevenAtRr,
          tickSize: position.contract.tickSize,
        });
      }
      let reason: ExitReason | undefined;
      let reference = 0;
      if (tick.ltp <= position.stopLossPrice) {
        reason = 'STOP_LOSS';
        reference = Math.min(tick.ltp, position.stopLossPrice);
      } else if (!position.runner && tick.ltp >= position.targetPrice) {
        reason = 'TARGET';
        reference = position.targetPrice;
      }
      if (reason === undefined) {
        continue;
      }
      position.exiting = true;
      void this.protectiveExit(position, reason, reference, tick.ltt);
    }
  }

  async close(): Promise<void> {
    this.listeners.clear();
    this.positions.clear();
  }

  private async protectiveExit(position: OpenPosition, reason: ExitReason, reference: number, at: number): Promise<void> {
    this.protectiveSequence += 1;
    const outcome = await this.send({
      correlationId: correlationIdFor('P', at, this.protectiveSequence),
      side: 'SELL',
      contract: position.contract,
      quantity: position.quantity,
      referencePrice: reference,
      reason,
    });
    if (outcome.kind === 'FILLED') {
      this.positions.delete(position.positionId);
      this.emit({
        kind: 'PROTECTIVE_EXIT_FILLED',
        underlying: position.underlying,
        positionId: position.positionId,
        quantity: outcome.filledQuantity,
        averagePrice: outcome.averagePrice,
        reason,
        at,
      });
      return;
    }
    // The stop or target was reached and the sell did not settle. The position may still be open at the venue.
    this.emit({
      kind: 'BROKER_MISMATCH',
      underlying: position.underlying,
      positionId: position.positionId,
      reason: `${reason} sell did not settle (${outcome.reason}); the position may still be open at the venue`,
    });
  }

  /** Sends one order. A gateway that throws is treated as UNCONFIRMED, so the agent halts instead of retrying. */
  private async send(order: GatewayOrder): Promise<GatewayOutcome> {
    // An id over the broker's limit is refused here, before any request, so it can never reach a venue.
    if (!fitsBrokerLimit(order.correlationId)) {
      return { kind: 'REJECTED', reason: `correlation id of ${order.correlationId.length} characters exceeds the broker limit; not sent` };
    }
    try {
      return await this.gateway.place(order);
    } catch (error) {
      this.options.logger.error('order gateway threw', { correlationId: order.correlationId, error: describe(error) });
      return { kind: 'UNCONFIRMED', reason: `order gateway threw: ${describe(error)}` };
    }
  }

  private emit(event: ExecutionEvent): void {
    queueMicrotask(() => {
      for (const listener of this.listeners) {
        listener(event);
      }
    });
  }
}

function describe(error: unknown): string {
  return error instanceof Error ? `${error.name}: ${error.message}`.slice(0, 240) : String(error).slice(0, 240);
}
