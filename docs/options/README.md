# Options Documentation

This folder holds **research and strategy notes** for index options buying (NIFTY,
SENSEX, and related context). They inform product thinking; **live trading parameters**
must always match current exchange and broker specifications.

## Reference Documents

1. [Deep research report](./deep-research-report%20(1).md) — Greeks, IV/OI,
   ATM vs ATM+1 templates, expiry behaviour, automation mapping.
2. [Options buying strategy development](./Options%20Buying%20Strategy%20Development.md) —
   Quant framing, microstructure, weekly-cycle narrative, order-flow ideas.

## Verify Before Encoding in `config/algo.yml`

> **Warning:** The strategy development note uses a **2026 regulatory narrative**
> (expiry days, lot sizes). Treat it as a framework, not as source of truth for
> production. Confirm every item below with **NSE/BSE circulars**, contract specs,
> and **DhanHQ** instrument data.

1. **Weekly and monthly expiry weekdays** for each index (NIFTY vs Sensex vs others).
2. **Lot size** and **tick size** per index and series (revisions happen).
3. **Quantity freeze** and any **order-slicing** limits for large clips.
4. **Cash settlement** rules and **last trading time** on expiry (no assumptions
   from blog-style copy).
5. **Holiday-adjusted** expiries and **special sessions** (Muhurat, etc.).
6. **Strike step** and **available expiries** in the chain your adapter returns.

## How This Relates to `algo_scalper_api`

- **Stable behaviour** comes from `app/services/options/`, `app/services/signal/`,
  `app/services/entries/`, and `config/algo.yml`.
- Research may suggest **order flow / Level 3** style edges; only adopt what your
  **data feeds** actually provide.
- After changing **calendar or sizing** assumptions, re-check **capital allocator**
  and **guards** against real contract multipliers.

## Maintenance

When exchange or broker specs change, update **this verification list** if new
ambiguities appear in the notes. Prefer **one canonical place** in repo docs or
comments near `algo.yml` for operational facts you rely on at runtime.
