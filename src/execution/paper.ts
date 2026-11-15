import type { ExitReason, Tick } from '../domain/types.js';
import { calculateTrailingStop, roundDownToTick, roundUpToTick } from '../options/pricing.js';
import type { EntryOrder, ExecutionEvent, ExecutionListener, ExecutionPort, ExitOrder } from './ports.js';

interface PaperPosition {
  readonly positionId: string;
  readonly underlying: string;
  readonly securityId: string;
  readonly exchangeSegment: string;
  readonly tickSize: number;
  readonly quantity: number;
  readonly averagePrice: number;
  readonly initialStopPrice: number;
  stopLossPrice: number;
  highWaterMark: number;
  readonly targetPrice: number;
  readonly trailingJump?: number | undefined;
  readonly breakevenAtRr?: number | undefined;
  readonly runner?: boolean | undefined;
}

export interface PaperExecutionOptions {
  readonly slippageBps: number;
  readonly now?: () => number;
}

/**
 * Simulated venue for paper trading. Entries fill at the reference premium plus
 * configured slippage, and the bracket (stop and target) is enforced against
 * the option's live LTP. A gap through the stop fills at the LTP, not at the
 * stop, which is the conservative choice. This is an approximation: queue
 * position, partial fills and exchange freeze limits are not modelled.
 */
export class PaperExecutionPort implements ExecutionPort {
  readonly protection: 'EXCHANGE_BRACKET' | 'CLIENT_SIDE' = 'CLIENT_SIDE';
  readonly mode = 'paper' as const;
  private readonly listeners = new Set<ExecutionListener>();
  private readonly positions = new Map<string, PaperPosition>();
  private readonly now: () => number;

  constructor(private readonly options: PaperExecutionOptions) {
    this.now = options.now ?? Date.now;
  }

  onEvent(listener: ExecutionListener): () => void {
    this.listeners.add(listener);
    return () => {
      this.listeners.delete(listener);
    };
  }

  async submitEntry(order: EntryOrder): Promise<void> {
    const price = roundUpToTick(
      order.entryReference * (1 + this.options.slippageBps / 10_000),
      order.contract.tickSize,
    );
    const at = this.now();
    this.positions.set(order.correlationId, {
      positionId: order.correlationId,
      underlying: order.underlying,
      securityId: order.contract.securityId,
      exchangeSegment: order.contract.exchangeSegment,
      tickSize: order.contract.tickSize,
      quantity: order.quantity,
      averagePrice: price,
      initialStopPrice: order.stopLossPrice,
      stopLossPrice: order.stopLossPrice,
      highWaterMark: price,
      targetPrice: order.targetPrice,
      trailingJump: order.trailingJump,
      breakevenAtRr: order.breakevenAtRr,
      runner: order.runner,
    });
    this.emitAsync({
      kind: 'ENTRY_FILLED',
      correlationId: order.correlationId,
      underlying: order.underlying,
      quantity: order.quantity,
      averagePrice: price,
      at,
    });
  }

  async submitExit(order: ExitOrder): Promise<void> {
    const position = this.positions.get(order.positionId);
    if (position === undefined) {
      this.emitAsync({
        kind: 'EXIT_REJECTED',
        correlationId: order.correlationId,
        underlying: order.underlying,
        positionId: order.positionId,
        reason: 'no open paper position with this id',
      });
      return;
    }
    const quantity = Math.min(order.quantity, position.quantity);
    const price = roundDownToTick(
      order.referencePrice * (1 - this.options.slippageBps / 10_000),
      position.tickSize,
    );
    this.positions.delete(order.positionId);
    this.emitAsync({
      kind: 'EXIT_FILLED',
      correlationId: order.correlationId,
      underlying: order.underlying,
      positionId: order.positionId,
      quantity,
      averagePrice: price,
      reason: order.reason,
      at: this.now(),
    });
  }

  onOptionTick(tick: Tick): void {
    for (const position of [...this.positions.values()]) {
      if (position.securityId !== tick.securityId || position.exchangeSegment !== tick.exchangeSegment) {
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
          tickSize: position.tickSize,
        });
      }
      let reason: ExitReason | undefined;
      let fill = 0;
      if (tick.ltp <= position.stopLossPrice) {
        reason = 'STOP_LOSS';
        fill = Math.min(tick.ltp, position.stopLossPrice);
      } else if (!position.runner && tick.ltp >= position.targetPrice) {
        reason = 'TARGET';
        fill = position.targetPrice;
      }
      if (reason === undefined) {
        continue;
      }
      this.positions.delete(position.positionId);
      this.emitAsync({
        kind: 'PROTECTIVE_EXIT_FILLED',
        underlying: position.underlying,
        positionId: position.positionId,
        quantity: position.quantity,
        averagePrice: fill,
        reason,
        at: tick.ltt,
      });
    }
  }

  async close(): Promise<void> {
    this.listeners.clear();
    this.positions.clear();
  }

  /** Emits outside the caller's stack so the agent never re-enters its own transition in progress. */
  private emitAsync(event: ExecutionEvent): void {
    queueMicrotask(() => {
      for (const listener of this.listeners) {
        listener(event);
      }
    });
  }
}
