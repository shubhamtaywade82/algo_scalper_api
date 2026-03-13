# Architecture Diagrams Index

This folder contains system diagrams for the Algo Scalper API: C4 levels, high-level architecture, and end-to-end flows. All diagrams are derived from the current codebase and use Mermaid for rendering (GitHub, VS Code, and most doc tools support Mermaid).

## Diagram Locations

| Diagram | File | Description |
|---------|------|-------------|
| **Complete set** | [complete-system-diagrams.md](complete-system-diagrams.md) | C4 Level 1–4, high-level process, signal→exit flow, tick/PnL data flow, entry pipeline, exit flow |
| **Legacy signal flow** | [legacy_diagrams.md](legacy_diagrams.md) | ASCII signal/scheduler and indicator flows (historical) |

## C4 Model (in complete-system-diagrams.md)

- **Level 1 — System Context:** Users and external systems (Trader, DhanHQ, Telegram, optional Authority server, OpenAI).
- **Level 2 — Containers:** Web, Trading Daemon, Jobs, Dashboard, PostgreSQL, Redis, and external systems.
- **Level 3 — Components:** Inside Trading Daemon (Supervisor + 11 services) and Web (API, ActionCable).
- **Level 4 — Code:** Sample code-level diagram (EntryGuardPipeline and guard classes).

## Other Architecture Docs (with diagrams)

- [../system_overview.md](../system_overview.md) — Process model (ASCII), high-level data flow (Mermaid), tick flow, exit flow.
- [../system-context.md](../system-context.md) — C1 context (flowchart).
- [../container-architecture.md](../container-architecture.md) — C2 containers (C4Container).
- [../component-map.md](../component-map.md) — C3 component groups and Supervisor graph.
- [../execution-flow.md](../execution-flow.md) — Trade lifecycle narrative (no diagram).
- [../diagrams.md](../diagrams.md) — Legacy high-level, signal pipeline, exit priority (links to this folder).

## Conventions

- **Process** = OS process (web, trading, jobs, dashboard).
- **Container** = C4 container (deployable/runnable boundary).
- **Component** = major in-process component (e.g. RiskManagerService).
- All Mermaid uses `flowchart` or `graph` for broad compatibility.
