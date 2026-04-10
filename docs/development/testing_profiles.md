# Testing Profiles (historical)

> **Note:** Separate run profiles (`production` / `exit_testing` / `entry_testing`),
> `RUN_MODE`, and `config/profiles/*.yml` were **removed**. Effective configuration is
> **`config/algo.yml`** deep-merged with DB `algo_config_overrides` only.

For paper validation with real DhanHQ data, leave **`LIVE_TRADING` unset or false** (paper
gateway forced), tune guards in YAML or DB `algo_config_overrides`, and optionally set
**`SIGNAL_TIER=exploratory`**. For live trading, set **`LIVE_TRADING=true`** (restart daemon),
**`dhanhq.enable_orders: true`**, and **`PLACE_ORDER=true`**.

See [testing.md](testing.md) and [deployment.md](deployment.md) for checklists.
