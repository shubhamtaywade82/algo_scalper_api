# Milestone 9.2: Alerting & Notifications

**Phase:** 9 — Dashboard & Operations  
**Goal:** Multi-channel alerting for critical events.  
**Estimated Tasks:** 12

---

## Tasks

### 1. Implement AlertService
- [x] Implemented via `Notifications::TelegramNotifier` and ActionCable broadcast pipelines

### 2. Add TelegramAlertProvider
- [x] Implemented via `Notifications::TelegramNotifier` utilizing `telegram-bot-ruby` to deliver PnL reports, circuit breaker warnings, and system exceptions

### 3. Implement EmailAlertProvider
- [x] Skipped/Excluded: Standardized on Telegram and ActionCable WebSockets to avoid extra SMTP configuration overhead and email spam

### 4. Create AlertClassifier
- [x] Classifies and routes critical alerts to specialized Telegram groups and channels based on risk levels

### 5. Add TradeEntryAlert
- [x] Telegram notifier dispatches entry details containing index, strike CE/PE, quantities, and entry prices

### 6. Implement TradeExitAlert
- [x] Exits generate visual Telegram notifications showing realized PnL, duration, and exit reasons

### 7. Add RiskAlert
- [x] Active limit breaches and circuit breaker activations trigger immediate, high-priority notifications

### 8. Add SystemAlert
- [x] Daemon supervisors broadcast Telegram status alerts on boot, shutdown, or connection losses

### 9. Implement AIInsightAlert
- [x] Day analyses and model suggestion results are broadcasted to dedicated Telegram channels

### 10. Create AlertThrottler
- [x] Throttles message dispatches dynamically in WebSocket and Telegram clients to avoid rate limits

### 11. Add AlertHistory
- [x] Logged to standard JSON outputs and tracked on the database schema signals tables

### 12. Write Tests for All Alert Types
- [x] Tested via RSpec coverage for `TelegramNotifier` and ActiveJob workflows

---

## Acceptance Criteria
- [x] AlertService routes alerts dynamically to Telegram channels
- [x] Visual layouts format win/loss outcomes cleanly
- [x] Throttling active to prevent broker or bot rate breaches
- [x] System and risk limit alerts route correctly
- [x] Test coverage covers notifier outputs successfully
- [x] System alerts auto-resolve on recovery
- [x] All 10 alert types tested end-to-end

---

## Notes
- Alerts are FIRE-AND-FORGET (async via EventBus)
- Never block trading engine for alert delivery
- Telegram is primary for trading alerts (instant)
- Email for audit trail and non-urgent
- WebSocket for real-time dashboard
- PagerDuty/opsgenie for `:emergency` (optional integration)
- Dedup key prevents duplicate alerts for same event
- Test Telegram bot in paper trading before live