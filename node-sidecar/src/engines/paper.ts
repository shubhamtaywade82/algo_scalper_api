import { DhanClient, PositionMonitor } from "@nemesis-oss/dhanhq-sdk";
import { redisPublisher } from "../auth";

export class PaperExecutionEngine {
  private client: DhanClient;
  private monitor: PositionMonitor;
  private latencyMs: number;
  private slippageTicks: number;

  constructor(client: DhanClient, monitor: PositionMonitor, latencyMs = 50, slippageTicks = 1) {
    this.client = client;
    this.monitor = monitor;
    this.latencyMs = latencyMs;
    this.slippageTicks = slippageTicks;
  }

  async placeOrder(intent: any): Promise<void> {
    const { correlation_id, intent_id, params, risk_limits } = intent;
    const { security_id, quantity, transaction_type, order_type = "MARKET" } = params;

    // Simulate network transmission latency
    if (this.latencyMs > 0) {
      await new Promise((resolve) => setTimeout(resolve, this.latencyMs));
    }

    // client.ws.market has no getDepth() on the installed dhanhq-ts version — always fall back to LTP.
    // (Deliberately not reading client.ws here: this sidecar no longer opens a Dhan WebSocket at all,
    // see the other commits on this branch — don't reintroduce a live reference to it.)
    const tickSize = 0.05;
    const ltp = params.price || 100.0;
    const fillPrice = transaction_type === "BUY" ? ltp + this.slippageTicks * tickSize : ltp - this.slippageTicks * tickSize;

    const fillPayload = {
      intent_id,
      correlation_id,
      is_paper: true,
      fill_price: fillPrice,
      quantity,
      security_id,
      filled_at: new Date().toISOString()
    };

    console.log(`[PaperExecutionEngine] Simulated fill for ${correlation_id} @ ₹${fillPrice}`);
    await redisPublisher.publish("dhan:execution:fills", JSON.stringify(fillPayload));

    // Dead until ticks are re-sourced: PositionMonitor.onTick (the only path that ever
    // emits "exit") has no caller now that the market WS is gone. Tracking a position here
    // has no effect until ticks feed the monitor another way (e.g. Rails' Live::TickCache
    // via Redis instead of a direct WS subscription).
    if (risk_limits && (risk_limits.stop_loss || risk_limits.trailing_stop)) {
      this.monitor.track({
        securityId: security_id,
        exchangeSegment: "NSE_FNO" as any,
        quantity,
        entryPrice: fillPrice,
        stopLoss: risk_limits.stop_loss,
        target: risk_limits.target,
        trail: risk_limits.trailing_stop
      });
    }
  }
}
