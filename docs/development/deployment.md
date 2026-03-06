# Deployment Guide

This document outlines the deployment strategy for the ARES Trading System.

## 1. Production Environment
- **OS**: Linux (Ubuntu 22.04+ recommended)
- **Process Manager**: `systemd` or `pm2` to manage the long-running trading daemon.
- **Reverse Proxy**: Nginx (serving the Rails API and Dashboard).

## 2. Infrastructure Setup
1.  **PostgreSQL**: Ensure `pg_hba.conf` allows connections from the application server.
2.  **Redis**: Enable persistence (`appendonly yes`) to prevent loss of tick/PnL caches during restarts.
3.  **DhanHQ Access**: Ensure the production IP is whitelisted if your broker requires IP-based security.

## 3. Deployment Steps
1.  **Clone & Install**:
    ```bash
    git clone ...
    bundle install --deployment --without development test
    ```
2.  **Precompile Assets**:
    ```bash
    bundle exec rails assets:precompile
    ```
3.  **Migration**:
    ```bash
    RAILS_ENV=production bundle exec rails db:migrate
    ```
4.  **Start Services**:
    - **Web Server**: `bundle exec puma -C config/puma.rb`
    - **Trading Daemon**: `ENABLE_TRADING_SERVICES=true bundle exec rake trading:daemon`

## 4. Monitoring
- **Logs**: Monitor `log/production.log` and `log/trading_daemon.log`.
- **Alerts**: The system integrates with Telegram for real-time notifications of circuit breaker trips or critical execution failures.
