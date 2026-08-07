import { DhanClient, PositionMonitor } from "@shubhamtaywade82/dhanhq-ts";
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

    // Try fetching live depth or fallback to LTP
    let fillPrice = 100.0;
    const tickSize = 0.05;

    try {
      const marketFeed = this.client.ws?.market as any;
      const depth = marketFeed && typeof marketFeed.getDepth === "function" ? marketFeed.getDepth(security_id) : null;
      if (depth && depth.bestAsk > 0 && depth.bestBid > 0) {
        if (transaction_type === "BUY") {
          fillPrice = depth.bestAsk + this.slippageTicks * tickSize;
        } else {
          fillPrice = depth.bestBid - this.slippageTicks * tickSize;
        }
      } else {
        const ltp = params.price || 100.0;
        fillPrice = transaction_type === "BUY" ? ltp + this.slippageTicks * tickSize : ltp - this.slippageTicks * tickSize;
      }
    } catch {
      fillPrice = params.price || 100.0;
    }

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

    // Register position with PositionMonitor for tick-driven trailing stop exit
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
