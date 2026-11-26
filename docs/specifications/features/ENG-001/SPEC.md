# ENG-001: Real Engineering Foundation and Architecture Deepening

## Overview
Establish rigorous software engineering discipline across the unified `algo-scalper` repository. This establishes a ubiquitous domain language via `GLOSSARY.md`, records foundational architectural trade-offs in `docs/adr/`, deepens god modules (`Entries::EntryGuard`), and ensures tight multi-stack feedback loops.

## Problem
The codebase previously suffered from:
1. Missing domain glossary: inconsistent terminology for core concepts across Rails, TypeScript, and PineScript.
2. Undocumented critical architectural decisions leading to repeated questions regarding execution posture, entry cutoffs, and time-stops.
3. Monolithic god modules (`Entries::EntryGuard` at 765 lines) mixing intent forwarding with 700 lines of legacy order execution logic.

## Scope

### In Scope
- Author `GLOSSARY.md` at repository root defining ubiquitous domain language for Indian F&O options scalping.
- Author foundational Architecture Decision Records (`docs/adr/ADR-001-polyglot-signal-execution-split.md`, `docs/adr/ADR-002-intraday-session-cutoffs.md`, `docs/adr/ADR-003-option-long-time-stop-invariant.md`).
- Deepen `Entries::EntryGuard` by extracting direct order placement into `Entries::DirectOrderPlacer`, shrinking `EntryGuard` to a clean dispatcher under 250 lines while preserving all existing test behavior.
- Verify multi-stack tests (Agent 1,713 tests, Dashboard 49 tests, Rails smoke specs).

### Out of Scope
- Rewriting the live DhanHQ market feed or WebSocket connection.
- Modifying live broker gateway order placement logic.

## Acceptance Criteria
- **ACC-001**: `GLOSSARY.md` exists at repository root defining the ubiquitous language across underlyings, regimes, postures, trade intents, and risk stops.
- **ACC-002**: `docs/adr/` contains ADR-001, ADR-002, and ADR-003 with explicit context, decision, and consequences.
- **ACC-003**: `Entries::EntryGuard` is refactored into a deep module under 250 lines that delegates direct execution to `Entries::DirectOrderPlacer`, and all entry guard tests pass.
- **ACC-004**: Multi-stack verification passes across Dashboard, Agent, and Rails smoke suites.
