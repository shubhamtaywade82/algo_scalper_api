# Testing Profiles (historical)

> **Note:** Separate run profiles (`production` / `exit_testing` / `entry_testing`),
> `RUN_MODE`, and `config/profiles/*.yml` were **removed**. Effective configuration is
> **`config/algo.yml`** deep-merged with DB `algo_config_overrides` only.

For paper validation with real DhanHQ data, use **`paper_trading.enabled: true`** and tune
guards or limits directly in YAML or via the settings API. For live trading, use
**`paper_trading.enabled: false`** with `dhanhq.enable_orders` and `PLACE_ORDER` gates.

See [testing.md](testing.md) and [deployment.md](deployment.md) for checklists.
