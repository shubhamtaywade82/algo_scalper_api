# Service Dependencies

Mermaid diagram visualizing how components interact within the system.

## Top-to-Bottom Interaction

```mermaid
flowchart TD

    subgraph Entry_Pipeline [Entry Pipeline]
        SignalScheduler --> SignalEngine
        SignalEngine --> ChainAnalyzer
        ChainAnalyzer --> EntryGuard
        EntryGuard --> OrderRouter
        OrderRouter --> DhanHQClient
    end

    subgraph Exit_Pipeline [Risk & Exit Pipeline]
        RiskManager --> UnifiedExitChecker
        UnifiedExitChecker --> ExitEngine
        ExitEngine --> OrderRouter
    end

    subgraph Data_Pipeline [Market Data Pipeline]
        DhanWS --> MarketFeedHub
        MarketFeedHub --> RedisTickCache
        RedisTickCache --> SignalEngine
        RedisTickCache --> RiskManager
    end

    subgraph Monitoring [Dashboard & Alerts]
        SignalEngine --> TelegramNotifier
        RiskManager --> TelegramNotifier
        DhanHQClient -- Webhooks --> OrderUpdateHub
    end
```

## Dependency Descriptions
- **SignalScheduler**: Periodically polls and triggers the Engine.
- **SignalEngine**: Depends on `RedisTickCache` for latest price and `IndicatorFactory` for TA.
- **EntryGuard**: Depends on `CircuitBreaker` and `PositionTracker` (Active counts).
- **RiskManager**: High-frequency loop polling `RedisTickCache` and evaluating `UnifiedExitChecker`.
- **OrderRouter**: Proxies calls to either `GatewayLive` or `GatewayPaper`.
