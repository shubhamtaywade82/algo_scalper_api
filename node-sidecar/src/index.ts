import dotenv from "dotenv";
import { createDhanClient } from "./auth";
import { startExecutor } from "./executor";
import { startAnalytics } from "./analytics";

dotenv.config();

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
