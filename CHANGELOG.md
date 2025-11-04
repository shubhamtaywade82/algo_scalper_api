# Changelog

## 2025-02-16
- Document live trading readiness audit covering instrument mapping, position sync, risk,
  feed health, and exit reliability gaps.

## 2025-02-15
- Document options-buying readiness, risk flow, and configuration switches in the README.

## 2025-02-14
- Ensure `Signal::Scheduler` runs as a singleton to prevent duplicate signal threads and add graceful shutdown.
- Replace `defined?` guards in the market stream initializer with explicit class usage and NameError fallbacks.
