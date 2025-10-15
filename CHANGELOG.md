# Changelog

## 2025-02-14
- Ensure `Signal::Scheduler` runs as a singleton to prevent duplicate signal threads and add graceful shutdown.
- Replace `defined?` guards in the market stream initializer with explicit class usage and NameError fallbacks.
