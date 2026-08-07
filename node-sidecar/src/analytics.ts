import { DhanClient, greeks } from "@shubhamtaywade82/dhanhq-ts";
import { redisPublisher } from "./auth";

export function startAnalytics(client: DhanClient): void {
  if (!client.ws || !client.ws.market) {
    console.log("[Analytics] WebSocket market feed not initialized, analytics module dormant.");
    return;
  }

  // Unhandled "error" events crash the process (Node EventEmitter default) — reconnects on
  // token rotation (see auth.ts) fire these; must be caught, not left to propagate.
  client.ws.market.on("error", (e: any) => {
    console.error("[Analytics] WebSocket market error:", e);
  });

  client.ws.market.on("tick", async (tick: any) => {
    try {
      if (!tick || !tick.securityId || !tick.ltp) return;

      const spot = tick.ltp;
      const strike = Math.round(spot / 50) * 50; // Dynamic ATM strike estimation for NIFTY

      const optionMetrics = greeks({
        spot: spot,
        strike: strike,
        timeToExpiry: 7 / 365,
        riskFreeRate: 0.065,
        volatility: 0.15,
        optionType: "call"
      });

      const redisKey = `dhan:market:greeks:${tick.securityId}`;
      await redisPublisher.set(redisKey, JSON.stringify(optionMetrics), "EX", 10);
    } catch (e) {
      // Suppress tick loop errors silently
    }
  });

  console.log("[Analytics] Real-time Greeks analytics engine started.");
}
