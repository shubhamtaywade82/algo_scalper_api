# Replay Modes

The paper trading runtime supports three execution modes:

## Replay Modes

1. **Live Market Paper Trading**:
   - Subscribes to the live DhanHQ tick WebSocket.
   - Routes virtual orders through the sandbox endpoint, updating the local portfolio database.

2. **Historical Replay**:
   - Replays historical intraday candles to test strategy decisions.
   - Used to verify that code changes do not alter historical outputs.

3. **Accelerated Replay**:
   - Replays historical logs at high speeds (e.g. 10x - 100x) to validate performance over extended periods.
