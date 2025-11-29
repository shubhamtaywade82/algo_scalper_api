# Documentation Index

This directory contains all documentation for the Algo Scalper API trading system.

## 📚 Documentation Structure

### Core System Documentation
- **[Codebase Status](./CODEBASE_STATUS.md)** - **CURRENT STATUS** - Single source of truth for all service implementation status, paper mode handling, thread safety, and production readiness
- **[Complete System Flow](./COMPLETE_SYSTEM_FLOW.md)** - Complete flow from Rails initialization through position exit, including all service interactions, data flows, and decision points
- **[Services Summary](./SERVICES_SUMMARY.md)** - Complete list of all services, their responsibilities, dependencies, and lifecycle
- [Repository Analysis](./REPO_ANALYSIS.md) - Comprehensive repository analysis and architecture overview

### [Architecture](./architecture/)
Core system architecture and component documentation:
- [Services Startup](./architecture/services_startup.md) - How services start and interact
- [Event Bus & Feed Listener](./architecture/nemesis_v3_event_bus_feed_listener.md) - NEMESIS V3 event system
- [Strike Selector](./architecture/nemesis_v3_strike_selector_complete.md) - Strike selection system
- [Derivative Chain Analyzer](./architecture/derivative_chain_analyzer_implementation.md) - Option chain analysis

### [Guides](./guides/)
User guides and how-to documentation:
- [Usage Guide](./guides/usage.md) - Getting started and operational procedures
- [DhanHQ Client](./guides/dhanhq-client.md) - DhanHQ API integration reference
- [Configuration](./guides/configuration.md) - DhanHQ and system configuration
- [WebSocket Guide](./guides/websocket.md) - WebSocket setup and data modes

### [Troubleshooting](./troubleshooting/)
Problem-solving and debugging guides:
- [WebSocket Issues](./troubleshooting/websocket.md) - WebSocket connection and feed problems
- [Ticker Issues](./troubleshooting/ticker.md) - Ticker channel and data problems

### [Development](./development/)
Development and testing documentation:
- [Testing Guidelines](./development/testing.md) - RSpec testing standards
- [Paper Trading](./development/paper_trading.md) - Paper trading mode setup

### [Operations](./operations/)
Operational and deployment documentation:
- [Health Checks](./operations/health_checks.md) - System health monitoring
- [Redis Keys](./operations/redis_keys.md) - Redis key structure
- [Rollout Procedures](./operations/rollout.md) - Deployment and rollout checklists

### [Strategies](./strategies/)
Trading strategy documentation:
- [Options Buying Strategies](./strategies/options_buying.md) - Options buying approach

### [Standards](./standards/)
Code standards and conventions:
- [Coding Conventions](../CODING_CONVENTIONS.md) - Link to root-level conventions
- [Cursor Rules](../CURSOR_RULES.md) - Link to root-level cursor rules

## 🚀 Quick Links

- [Main README](../README.md) - Project overview and quick start
- [Changelog](../CHANGELOG.md) - Version history
- [Requirements](../requirements.md) - System requirements

## 📝 Document Status

All documentation in this folder is maintained and kept up-to-date with the codebase. If you find outdated information, please update the relevant document or create an issue.

