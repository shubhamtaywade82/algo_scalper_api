import { DhanClient } from "@shubhamtaywade82/dhanhq-ts";
import Redis from "ioredis";

const redisUrl = process.env.REDIS_URL || "redis://127.0.0.1:6379/0";
export const redisSubscriber = new Redis(redisUrl);
export const redisPublisher = new Redis(redisUrl);

export async function createDhanClient(): Promise<DhanClient> {
  const clientId = (await redisPublisher.get("dhan:auth:client_id")) || process.env.DHAN_CLIENT_ID || "";

  const client = new DhanClient({
    clientId,
    tokenProvider: async () => {
      const token = await redisPublisher.get("dhan:auth:access_token");
      if (!token) {
        throw new Error("[Sidecar] Token missing in Redis key dhan:auth:access_token. Token Authority (Rails) must refresh token.");
      }
      return token;
    }
  });

  redisSubscriber.subscribe("dhan:auth:rotated", (err) => {
    if (err) {
      console.error("[Sidecar] Failed to subscribe to dhan:auth:rotated channel:", err);
    } else {
      console.log("[Sidecar] Subscribed to dhan:auth:rotated channel from Token Authority (Rails).");
    }
  });

  redisSubscriber.on("message", async (channel) => {
    if (channel === "dhan:auth:rotated") {
      console.log("[Sidecar] Token rotated notification received from Rails. Reconnecting WebSockets...");
      try {
        if (client.ws) {
          await client.ws.disconnect();
          await client.ws.connect();
        }
      } catch (e) {
        console.error("[Sidecar] Failed to reconnect WebSocket after token rotation:", e);
      }
    }
  });

  return client;
}
