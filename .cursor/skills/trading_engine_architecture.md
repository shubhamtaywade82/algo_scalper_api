# Trading Engine Architecture

The system follows a modular pipeline to handle market data and execute SMC logic.

## Pipeline Flow
1. **Market Data Layer**: 
   - DhanHQ WebSocket feed (MarketTick).
   - Historical candle fetcher (Dhan::MarketDataService).
2. **Candle Construction**:
   - `CandleSeries` builder aggregating ticks into M1/M5/M15/H1 timeframes.
3. **SMC Structure Engine**:
   - `SmcAnalyzer`: Detects BOS, CHoCH, and Swing points.
   - `DisplacementDetector`: Validates institutional moves.
   - `ImbalanceService`: Tracks unmitigated FVGs.
4. **Signal Generator**:
   - Combines structure and imbalance info into potential entry signals.
5. **Risk Manager**:
   - `RiskManagerService`: Enforces daily limits, trade caps, and SL/TP validation.
6. **Order Executor**:
   - `Orders::Gateway`: High-level interface for Paper (Simulated) or Live (DhanHQ) execution.
7. **Position Manager**:
   - `TrailingEngine`: Manages active trades and trailing stop losses.

## Core Infrastructure
- **Redis**: Low-latency state grid for active structural levels.
- **PostgreSQL**: Long-term persistence for trade history and logs.
- **Solid Queue**: Recurring jobs for instrument synchronization and technical analysis.
