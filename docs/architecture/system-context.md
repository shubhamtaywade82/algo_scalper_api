# C1: System Context Diagram

This document describes the high-level relationship between Algo Scalper API and its environment.

## Overview
Algo Scalper API is an automated trading system that acts as a bridge between Strategy logic and Broker execution.

```mermaid
flowchart TD
    Trader((Trader))
    ares[Algo Scalper API Trading System]
    dhan[DhanHQ API]
    telegram[Telegram]

    Trader -- "Configures & Monitors" --> ares
    ares -- "Executes Orders & Fetches Feed" --> dhan
    ares -- "Sends Alerts" --> telegram
```

## External Actors
- **Trader**: The human operator who manages the `algo.yml` and views the dashboard.
- **DhanHQ API**: The primary gateway for the Indian Stock Market (NSE/BSE/MCX).
- **Telegram**: Used for low-latency asynchronous notifications on system health and trade status.
