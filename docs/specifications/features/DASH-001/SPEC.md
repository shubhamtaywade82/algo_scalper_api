# DASH-001: Dashboard UI/UX and Functional Fixes

## Overview
Comprehensive remediation of UI/UX, functional, responsiveness, and state synchronization issues across the Algo Scalper dashboard.

## Problem
The dashboard has functional defects including a stale closure in market depth polling, non-filtering column toggles in the option chain, unhandled action buttons, and unsynchronized tab state. Additionally, on mobile and tablet devices, the sidebar squishes the screen layout, ticker quotes disappear from the header, the terminal sidebar is completely unreachable, and critical trade exit buttons require cumbersome horizontal scrolling.

## Scope

### In Scope
- Fix `useDepth` reactive symbol closure bug in `MarketWatch.jsx` and `useDepth.js` so selecting BANKNIFTY or SENSEX fetches and displays the correct depth for that symbol.
- Implement column filtering in `OptionChain.jsx` so clicking "LTP", "OI", or "Greeks" filters the table columns according to the selected view mode.
- Wire unhandled buttons: "Strategy Builder" in `OptionChain.jsx` to navigate to `/strategies/creator`, and placeholder actions in `Backtester.jsx` and `Reports.jsx`.
- Fix reactive tab synchronization in `Portfolio.jsx` and `StrategiesHub.jsx` so navigating between tabs via sidebar or URL updates the active tab.
- Improve mobile and tablet responsiveness:
  - Add mobile overlay drawer support for `Sidebar.jsx` with backdrop and responsive toggle.
  - Add responsive ticker pill in `Header.jsx` for viewports under `xl:` so mobile/tablet users can see live market quotes.
  - Add a toggle button in `ConfluenceTerminal.jsx` to open `TerminalSidebar` on mobile/tablet screens.
  - Optimize `StatsBar.jsx` layout for mobile devices (`grid-cols-2` on mobile).
- Verify each view and responsive behavior in the browser via `browser_subagent`.

### Out of Scope
- Backend trading algorithm modifications.
- Modifications to Solid Queue recurring schedules or DhanHQ broker API gateways.

## Acceptance Criteria
- **ACC-001**: In `MarketWatch.jsx`, switching the symbol dropdown to `BANKNIFTY` or `SENSEX` passes the new symbol to `useDepth` and fetches depth data for the chosen symbol.
- **ACC-002**: In `OptionChain.jsx`, toggling between `LTP`, `OI`, and `Greeks` visibly filters the table columns to only display columns corresponding to that view mode (or all for Greeks), maintaining strike price in the center.
- **ACC-003**: The "Strategy Builder" button in `OptionChain.jsx` navigates to `/strategies/creator`, and tab navigation in `Portfolio.jsx` and `StrategiesHub.jsx` reactively synchronizes when URL search parameters or props change.
- **ACC-004**: On mobile viewports (`< 768px`), `Sidebar.jsx` acts as a slide-out overlay drawer without squishing the page content, and `Header.jsx` displays a compact active index ticker.
- **ACC-005**: In `ConfluenceTerminal.jsx`, mobile and tablet users can toggle the `TerminalSidebar` drawer to inspect open positions, Greeks, and market depth.
- **ACC-006**: All existing unit tests pass, Vite build succeeds without error, and browser verification confirms visual rendering and interactions across desktop and mobile viewports.
