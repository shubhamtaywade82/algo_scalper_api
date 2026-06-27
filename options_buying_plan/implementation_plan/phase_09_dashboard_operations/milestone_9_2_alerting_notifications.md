# Milestone 9.2: Alerting & Notifications

**Phase:** 9 — Dashboard & Operations  
**Goal:** Multi-channel alerting for critical events.  
**Estimated Tasks:** 12

---

## Tasks

### 1. Implement AlertService
- [ ] Create `app/services/alert_service.rb`
- [ ] Interface: `notify(alert) -> Result`
- [ ] Alert structure:
  ```ruby
  Alert = Struct.new(:type, :severity, :title, :message, :data, :channels, :dedup_key)
  ```
- [ ] Severity: `:info`, `:warning`, `:critical`, `:emergency`
- [ ] Channels: `[:telegram, :email, :websocket, :webhook]`
- [ ] Async: publish to `alerts` channel, consumers handle delivery

### 2. Add TelegramAlertProvider
- [ ] Create `app/services/alerts/providers/telegram_provider.rb`
- [ ] Use `telegram-bot-ruby` gem
- [ ] Bot token from credentials
- [ ] Chat IDs: configured per severity (ops chat, trading chat, admin chat)
- [ ] Formatting: MarkdownV2 with code blocks for data
- [ ] Rate limit: 30 messages/sec (Telegram limit)
- [ ] Retry on failure with exponential backoff

### 3. Implement EmailAlertProvider
- [ ] Create `app/services/alerts/providers/email_provider.rb`
- [ ] Use `ActionMailer` with SMTP (SendGrid, SES, etc.)
- [ ] Templates: `alert_mailer/alert_email.html.erb`
- [ ] Recipients: configured per severity
- [ ] Critical/emergency: immediate, high priority
- [ ] Info/warning: batched digest (hourly)

### 4. Create AlertClassifier
- [ ] Create `app/services/alerts/alert_classifier.rb`
- [ ] Map alert types to severity:
  - `trade_entry`, `trade_exit` → `:info`
  - `stop_loss_hit`, `target_hit`, `partial_exit` → `:info`
  - `structure_warning`, `iv_warning`, `liquidity_warning` → `:warning`
  - `risk_limit_breach`, `margin_call`, `emergency_exit` → `:critical`
  - `system_failure`, `data_feed_down`, `broker_disconnect` → `:emergency`
- [ ] Channel routing per severity

### 5. Add TradeEntryAlert
- [ ] Create `app/services/alerts/trade_entry_alert.rb`
- [ ] Trigger: after successful order fill
- [ ] Data: setup type, instrument, strike, entry, SL, targets, qty, score
- [ ] Template: "🟢 ENTRY: ORB Long NIFTY 25000 CE @ 185 | SL 170 | T1 210 T2 235 | Qty 50 | Score 87"
- [ ] Channel: Telegram (trading chat), WebSocket

### 6. Implement TradeExitAlert
- [ ] Create `app/services/alerts/trade_exit_alert.rb`
- [ ] Trigger: position closed (any reason)
- [ ] Data: entry/exit, P&L, R-multiple, hold time, exit reason, MFE/MAE
- [ ] Template: "🔴 EXIT: ORB Long NIFTY 25000 CE @ 210 | P&L +2500 (+1.25R) | Held 42m | Reason: Target 1"
- [ ] Color: green for win, red for loss
- [ ] Channel: Telegram, WebSocket

### 7. Add RiskAlert
- [ ] Create `app/services/alerts/risk_alert.rb`
- [ ] Trigger: risk limit breached or threshold approached
- [ ] Types:
  - `daily_loss_50%`: "⚠️ Daily loss at 50% limit (₹25,000/₹50,000)"
  - `daily_limit_hit`: "🛑 DAILY LOSS LIMIT HIT - Trading halted"
  - `margin_utilization_80%`: "⚠️ Margin at 80%"
  - `position_limit`: "⚠️ Max NIFTY positions reached"
- [ ] Severity: `:warning` at 50%, `:critical` at 80%, `:emergency` at 100%
- [ ] Channel: All (Telegram, Email, WebSocket, PagerDuty)

### 8. Add SystemAlert
- [ ] Create `app/services/alerts/system_alert.rb`
- [ ] Trigger: infrastructure issues
- [ ] Types:
  - `dhanhq_rest_down`: "🔴 DhanHQ REST API unreachable"
  - `dhanhq_ws_disconnected`: "🔴 Market data feed lost"
  - `redis_down`: "🔴 Cache unavailable"
  - `db_slow`: "⚠️ Database latency > 1s"
  - `ai_gateway_degraded`: "⚠️ AI Gateway on fallback provider"
  - `queue_backlog`: "⚠️ Solid Queue depth > 1000"
- [ ] Auto-resolve alert when recovered
- [ ] Channel: Telegram (ops), Email (critical), PagerDuty (emergency)

### 9. Implement AIInsightAlert
- [ ] Create `app/services/alerts/ai_insight_alert.rb`
- [ ] Trigger: AI analysis with high-confidence actionable insight
- [ ] Types:
  - `regime_change`: "📊 Regime shift: NIFTY trending_up → ranging"
  - `structure_break`: "📉 CHOCH detected on NIFTY 15m"
  - `liquidity_sweep`: "💧 Liquidity sweep at 25050, reversal likely"
  - `iv_crush_imminent`: "⚡ IV crush risk high for 25000 CE (earnings tomorrow)"
- [ ] Severity: `:info` or `:warning`
- [ ] Channel: Telegram (trading), WebSocket

### 10. Create AlertThrottler
- [ ] Create `app/services/alerts/alert_throttler.rb`
- [ ] Per alert type (dedup_key): max 1 per 5 minutes
- [ ] Per channel: max 30/min (Telegram), 10/min (Email)
- [ ] Burst allowance: 5 immediate, then throttle
- [ ] Store throttle state in Redis with TTL
- [ ] Bypass throttle for `:emergency` severity

### 11. Add AlertHistory
- [ ] Create `app/models/alert_history.rb`
- [ ] Table: `alert_histories` (type, severity, title, message, data, channels, sent_at, acknowledged_at)
- [ ] Index: `(severity, sent_at)`, `(dedup_key, sent_at)`
- [ ] Retention: 90 days
- [ ] API: `GET /api/v1/alerts/history` with filters

### 12. Write Tests for All Alert Types
- [ ] Create `spec/services/alert_service_spec.rb`
- [ ] Mock providers (Telegram, Email, WebSocket)
- [ ] Test each alert type:
  - Correct formatting and data
  - Severity classification
  - Channel routing
  - Throttling behavior
  - Emergency bypass
- [ ] Integration: full alert flow from engine → service → provider

---

## Acceptance Criteria
- [ ] AlertService delivers to all configured channels
- [ ] Telegram alerts formatted correctly with Markdown
- [ ] Email alerts use templates, batched for non-critical
- [ ] Throttling prevents spam (test: 100 rapid alerts → < 10 delivered)
- [ ] Emergency alerts bypass throttle
- [ ] Alert history queryable and retained 90 days
- [ ] System alerts auto-resolve on recovery
- [ ] All 10 alert types tested end-to-end

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