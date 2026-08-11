import { DhanClient, OrderTracker, PositionMonitor } from "@shubhamtaywade82/dhanhq-ts";
import { redisPublisher } from "../auth";

export class LiveExecutionEngine {
  private client: DhanClient;
  private tracker: OrderTracker;
  private monitor: PositionMonitor;

  constructor(client: DhanClient, tracker: OrderTracker, monitor: PositionMonitor) {
    this.client = client;
    this.tracker = tracker;
    this.monitor = monitor;
  }

  async placeOrder(intent: any): Promise<void> {
    const { correlation_id, intent_id, params, risk_limits } = intent;
    const { security_id, quantity, transaction_type, order_type = "MARKET", exchange_segment = "NSE_FNO", price = 0 } = params;

    console.log(`[LiveExecutionEngine] Placing live order for correlationId: ${correlation_id}`);

    // This can never resolve today: OrderTracker.onOrderUpdate was only ever fed by the
    // client.ws.orders.on("order", ...) listener this branch deleted (WS collided with
    // Rails' own Dhan WebSocket clients — see the other commits on this branch). Reviving
    // this live-intent path requires sourcing fills another way (e.g. Rails'
    // Live::OrderUpdateHub over Redis) instead of re-opening a WebSocket here.
    const settled = this.tracker.waitFor(correlation_id, { timeoutMs: 30000 });

    await this.client.orders.place({
      correlationId: correlation_id,
      securityId: security_id,
      exchangeSegment: exchange_segment,
      transactionType: transaction_type,
      orderType: order_type,
      quantity: quantity,
      price: price,
      productType: "INTRADAY"
    });

    const fill = await settled;

    const fillPayload = {
      intent_id,
      correlation_id,
      is_paper: false,
      fill_price: fill.averagePrice || price,
      quantity: fill.filledQuantity || quantity,
      security_id,
      filled_at: new Date().toISOString()
    };

    await redisPublisher.publish("dhan:execution:fills", JSON.stringify(fillPayload));

    // Dead until ticks are re-sourced: PositionMonitor.onTick (the only path that ever
    // emits "exit") has no caller now that the market WS is gone. Tracking a position here
    // has no effect until ticks feed the monitor another way (e.g. Rails' Live::TickCache
    // via Redis instead of a direct WS subscription).
    if (risk_limits && (risk_limits.stop_loss || risk_limits.trailing_stop)) {
      this.monitor.track({
        securityId: security_id,
        exchangeSegment: exchange_segment as any,
        quantity: fill.filledQuantity || quantity,
        entryPrice: fill.averagePrice || price,
        stopLoss: risk_limits.stop_loss,
        target: risk_limits.target,
        trail: risk_limits.trailing_stop
      });
    }
  }
}
