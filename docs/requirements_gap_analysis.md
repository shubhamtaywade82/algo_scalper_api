# Requirements Gap Analysis

This document compares the implementation in `algo_scalper_api` against the system expectations captured in [`requirements.md`](../requirements.md).

## 1. Dependencies & Runtime Infrastructure
- ✅ Sidekiq and `concurrent-ruby` are now declared in the Gemfile so the app can schedule jobs and manage thread-safe caches as required by the spec.【F:Gemfile†L15-L38】
- ✅ Active Job targets Sidekiq in every environment, with Redis configuration handled via `config/initializers/sidekiq.rb`.【F:config/application.rb†L33-L41】【F:config/environments/production.rb†L50-L55】【F:config/initializers/sidekiq.rb†L1-L12】

## 2. Database Schema & Models
- ✅ A migration creates the `instruments`, `derivatives`, and `position_trackers` tables demanded by the trading requirements.【F:db/migrate/20241015120000_create_trading_core_tables.rb†L1-L47】
- ✅ New ActiveRecord models encapsulate subscriptions, derivative lookup, and trailing-stop tracking logic aligned with the specification.【F:app/models/instrument.rb†L1-L35】【F:app/models/derivative.rb†L1-L27】【F:app/models/position_tracker.rb†L1-L45】

## 3. Data & Streaming Services
- ✅ `Live::MarketFeedHub`, `Live::OrderUpdateHub`, and the new `Live::OrderUpdateHandler` marshal WebSocket ticks and order updates while updating `TickCache` and trackers.【F:app/services/live/market_feed_hub.rb†L1-L118】【F:app/services/live/order_update_hub.rb†L1-L112】【F:app/services/live/order_update_handler.rb†L1-L60】
- ✅ `Trading::DataFetcherService` wraps the DhanHQ REST API to provide historical candles, option chains, and derivative quotes for the analytics pipeline.【F:app/services/trading/data_fetcher_service.rb†L1-L63】

## 4. Risk Management Loop
- ✅ `Live::RiskManagerService` runs a five-second loop that computes BigDecimal P&L, manages high-water marks, and issues exits using live ticks and Dhan positions.【F:app/services/live/risk_manager_service.rb†L1-L112】

## 5. Trading Intelligence & Execution
- ✅ Indicator helpers (`Trading::Indicators`) compute RSI, ATR, and Supertrend inputs for signal generation.【F:app/services/trading/indicators.rb†L1-L63】
- ✅ `Trading::TrendIdentifier`, `Trading::StrikeSelector`, and `Trading::TradingService` coordinate signal evaluation, strike selection, pyramiding limits, and Super Order placement.【F:app/services/trading/trend_identifier.rb†L1-L33】【F:app/services/trading/strike_selector.rb†L1-L31】【F:app/services/trading/trading_service.rb†L1-L82】
- ✅ `TradingWorker` schedules the execution cycle through Sidekiq/Active Job integration.【F:app/jobs/trading_worker.rb†L1-L7】

## 6. API Surface & Scheduling
- ✅ `config/initializers/dhanhq_streams.rb` now boots the market data hub, order handlers, and risk manager whenever DhanHQ is enabled, ensuring the autonomous loop runs continuously.【F:config/initializers/dhanhq_streams.rb†L1-L37】
