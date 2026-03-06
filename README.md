# Algorithmic Scalper API (ARES)

A production-grade algorithmic trading system built with Ruby on Rails, designed for high-frequency scalping on Indian Indices (Nifty, BankNifty) via the DhanHQ API.

## 🚀 System Overview

ARES is an institutional-grade trading bot that automates the entire trade lifecycle—from signal identification using technical analysis (Supertrend, ADX, SMC) to dynamic risk-managed exits. It features a unique **Process-Isolated Execution Engine** that ensures low-latency market data processing and order execution separate from the web/dashboard overhead.

### Key Features
- **Multi-Strategy Engine**: Dynamic switching between Supertrend-based trend following and Advanced Strategy Recommendations.
- **Real-time WebSocket Hub**: High-performance tick ingestion with automatic reconnection.
- **Institutional Risk Management**: Prioritized exit hierarchy including Stop-Loss, Take-Profit, Trailing Stops, and Early Trend Failure detection.
- **Automatic Broker Reconciliation**: Ensures system state is always synchronized with the DhanHQ backend.
- **Paper & Live Trading**: Seamless toggle for strategy validation before capital deployment.

## 📚 Documentation Index

The system documentation is reconstructed directly from the codebase (Source of Truth).

### [Architecture](file:///home/nemesis/project/trading-workspace/algo_scalper_api/docs/architecture/system_overview.md)
- [System Overview](file:///home/nemesis/project/trading-workspace/algo_scalper_api/docs/architecture/system_overview.md): Core design and registry model.
- [Component Map](file:///home/nemesis/project/trading-workspace/algo_scalper_api/docs/architecture/components.md): Deep dive into services and responsibilities.
- [Flow Diagrams](file:///home/nemesis/project/trading-workspace/algo_scalper_api/docs/architecture/diagrams.md): Visualizing Signal-to-Exit pipelines.

### [Trading Logic](file:///home/nemesis/project/trading-workspace/algo_scalper_api/docs/trading/signal_engine.md)
- [Signal Engine](file:///home/nemesis/project/trading-workspace/algo_scalper_api/docs/trading/signal_engine.md): Indicators and validation filters.
- [Trade Lifecycle](file:///home/nemesis/project/trading-workspace/algo_scalper_api/docs/trading/lifecycle.md): End-to-end trace of a single trade.

### [Risk & Resilience](file:///home/nemesis/project/trading-workspace/algo_scalper_api/docs/risk/risk_management.md)
- [Risk Rules](file:///home/nemesis/project/trading-workspace/algo_scalper_api/docs/risk/risk_management.md): SL/TP and Trailing Stop logic.
- [Safety Mechanisms](file:///home/nemesis/project/trading-workspace/algo_scalper_api/docs/risk/safety_mechanisms.md): Circuit Breakers and Error Handling.

### [Infrastructure](file:///home/nemesis/project/trading-workspace/algo_scalper_api/docs/infrastructure/dhanhq_broker.md)
- [Broker Integration](file:///home/nemesis/project/trading-workspace/algo_scalper_api/docs/infrastructure/dhanhq_broker.md): Authentication and Order Routing.
- [WebSocket Hub](file:///home/nemesis/project/trading-workspace/algo_scalper_api/docs/infrastructure/websocket_hub.md): Real-time data pipeline.
- [State & Redis](file:///home/nemesis/project/trading-workspace/algo_scalper_api/docs/infrastructure/redis_state.md): Low-latency persistence.

### [Guides](file:///home/nemesis/project/trading-workspace/algo_scalper_api/docs/guides/setup.md)
- [Setup Guide](file:///home/nemesis/project/trading-workspace/algo_scalper_api/docs/guides/setup.md): Installation and configuration.
- [Troubleshooting](file:///home/nemesis/project/trading-workspace/algo_scalper_api/docs/guides/troubleshooting.md): Operational health and common fixes.

---

## 🛠 Tech Stack
- **Languages**: Ruby 3.3, TypeScript (UI)
- **Framework**: Rails 7 (API Mode)
- **State Store**: Redis (Real-time), PostgreSQL (Persistence)
- **Communication**: ActionCable (WebSockets), HTTP (Broker)
- **Monitoring**: Sidekiq, ActiveSupport Notifications

## ⚖️ License
This project is proprietary and confidential. Unauthorized copying of files via any medium is strictly prohibited.