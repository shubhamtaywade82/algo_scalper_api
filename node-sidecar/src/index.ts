import dotenv from "dotenv";
import { createDhanClient } from "./auth";
import { startExecutor } from "./executor";
import { startAnalytics } from "./analytics";

dotenv.config();

// Default Node behavior is to crash the process on these, which kills the whole `bin/dev`
// foreman group (any Procfile process exiting triggers SIGTERM to all). This is an auxiliary
// execution/analytics sidecar — it must never take the Rails trading daemon down with it.
process.on("uncaughtException", (e) => console.error("[Sidecar] Uncaught exception:", e));
process.on("unhandledRejection", (e) => console.error("[Sidecar] Unhandled rejection:", e));

async function main() {
  console.log("=================================================");
  console.log("Starting DhanHQ-TS Execution & Analytics Sidecar");
  console.log(`Mode: ${process.env.TRADING_MODE || "paper"}`);
  console.log("=================================================");

  try {
    const client = await createDhanClient();
    await startExecutor(client);
    startAnalytics(client);

    console.log("[Sidecar] Process ready and listening for Rails Redis events.");
  } catch (e) {
    console.error("[Sidecar] Initialization error:", e);
  }
}

main();
