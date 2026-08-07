import { DhanClient, OrderTracker, PositionMonitor, Pipeline, createSkillRegistry } from "@shubhamtaywade82/dhanhq-ts";
import Redis from "ioredis";
import { redisPublisher } from "./auth";
import { PaperExecutionEngine } from "./engines/paper";
import { LiveExecutionEngine } from "./engines/live";

const redisUrl = process.env.REDIS_URL || "redis://127.0.0.1:6379/0";
const intentSubscriber = new Redis(redisUrl);

export async function startExecutor(client: DhanClient): Promise<void> {
  const tracker = new OrderTracker();
  const monitor = new PositionMonitor();
  const skills = createSkillRegistry();

  const isLive = process.env.TRADING_MODE === "live";
  const paperEngine = new PaperExecutionEngine(client, monitor);
  const liveEngine = new LiveExecutionEngine(client, tracker, monitor);

  // Set up WebSocket listeners if available
  if (client.ws) {
    client.ws.orders?.on("order", (state: any) => tracker.onOrderUpdate(state));
    client.ws.market?.on("tick", (tick: any) => monitor.onTick(tick));
  }

  // Handle position exits emitted by PositionMonitor
  monitor.on("exit", async (signal: any) => {
    console.log(`[PositionMonitor] Exit triggered: ${signal.reason}, PnL: ${signal.pnl}`);
    const exitPayload = {
      position_id: signal.positionId,
      correlation_id: signal.correlationId || signal.positionId,
      exit_price: signal.exitPrice,
      pnl: signal.pnl,
      reason: signal.reason,
      is_paper: !isLive,
      exited_at: new Date().toISOString()
    };
    await redisPublisher.publish("dhan:execution:exits", JSON.stringify(exitPayload));
  });

  intentSubscriber.subscribe("dhan:execution:intents", (err) => {
    if (err) console.error("[Sidecar Executor] Subscribe error:", err);
    else console.log("[Sidecar Executor] Subscribed to dhan:execution:intents");
  });

  intentSubscriber.on("message", async (channel, message) => {
    if (channel !== "dhan:execution:intents") return;

    try {
      const intent = JSON.parse(message);
      console.log(`[Sidecar Executor] Processing intent ${intent.intent_id} (${intent.strategy})`);

      // Pre-trade risk pipeline check
      const pipeline = new Pipeline({
        limits: { maxQuantity: 500, dailyMaxLoss: 10000 }
      });
      await pipeline.run({ args: intent.params });

      // Check if intent is a defined-risk spread skill (e.g., bull_call_spread, iron_condor)
      if (intent.strategy && intent.strategy !== "buy_option" && intent.strategy !== "naked") {
        try {
          const { intent: skillIntent } = await skills.call(intent.strategy, intent.params, client);
          console.log(`[Sidecar Executor] Resolved Skill ${intent.strategy} legs:`, (skillIntent as any)?.legs);
        } catch (e) {
          console.warn(`[Sidecar Executor] Skill resolution for ${intent.strategy} skipped fallback to raw execution:`, e);
        }
      }

      if (isLive) {
        await liveEngine.placeOrder(intent);
      } else {
        await paperEngine.placeOrder(intent);
      }
    } catch (e) {
      console.error("[Sidecar Executor] Execution failed:", e);
    }
  });
}
