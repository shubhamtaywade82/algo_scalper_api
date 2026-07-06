// Route constants — single source of truth for all navigation
export const ROUTES = {
  // Auth
  LOGIN: '/login',
  REGISTER: '/register',

  // Main
  DASHBOARD: '/',

  // Market
  MARKET_WATCH: '/market-watch',
  OPTION_CHAIN: '/option-chain',
  MARKET_DATA: '/market-data/:symbol',

  // Portfolio
  POSITIONS: '/positions',
  ORDERS: '/orders',
  HOLDINGS: '/holdings',
  FUNDS: '/funds',

  // Analytics
  REPORTS: '/reports',
  PERFORMANCE: '/performance',
  TRADE_LOG: '/trade-log',

  // Strategies
  STRATEGIES: '/strategies',
  STRATEGY_CREATOR: '/strategies/creator',
  STRATEGY_DETAIL: '/strategies/:id',
  BACKTESTER: '/backtester',
  REPLAY: '/replay',

  // System
  LOGS: '/logs',
  ALERTS: '/alerts',
  SCHEDULER: '/scheduler',
  SETTINGS: '/settings',

  // Existing routes (keep for backward compat)
  ALPHA: '/alpha',
  SIGNALS: '/signals',
  OPTION_SCALPER: '/option-scalper',
  ANALYSIS: '/analysis',
  LEDGER: '/ledger',
  CHARTS: '/charts',
  TRAIL_ENGINE: '/trail-engine',
}

// Sidebar section labels
export const NAV_SECTIONS = {
  MAIN: { id: 'main', label: 'Main' },
  MARKET: { id: 'market', label: 'Market' },
  PORTFOLIO: { id: 'portfolio', label: 'Portfolio' },
  ANALYTICS: { id: 'analytics', label: 'Analytics' },
  SYSTEM: { id: 'system', label: 'System' },
}

export const navigationConfig = [
  {
    section: NAV_SECTIONS.MAIN,
    items: [
      { id: 'dashboard', label: 'Dashboard', href: ROUTES.DASHBOARD, icon: 'dashboard', end: true },
      { id: 'strategies', label: 'Strategies', href: ROUTES.STRATEGIES, icon: 'strategies' },
      { id: 'backtester', label: 'Backtester', href: ROUTES.BACKTESTER, icon: 'strategies' }, // reuses strategies icon/similar
      { id: 'replay', label: 'Replay', href: ROUTES.REPLAY, icon: 'alpha' },
      { id: 'reports', label: 'Reports', href: ROUTES.REPORTS, icon: 'reports' }
    ],
  },
  {
    section: NAV_SECTIONS.MARKET,
    items: [
      { id: 'market-watch', label: 'Market Watch', href: ROUTES.MARKET_WATCH, icon: 'marketWatch' },
      { id: 'option-chain', label: 'Option Chain', href: ROUTES.OPTION_SCALPER, icon: 'optionChain' }, // Maps to option scalper chain
      { id: 'market-data', label: 'Market Data', href: ROUTES.CHARTS, icon: 'charts' } // Maps to charts
    ],
  },
  {
    section: NAV_SECTIONS.PORTFOLIO,
    items: [
      { id: 'positions', label: 'Positions', href: ROUTES.DASHBOARD, icon: 'positions' }, // Existing positions are on dashboard
      { id: 'orders', label: 'Orders', href: ROUTES.LEDGER, icon: 'ledger' }, // Ledger acts as orders or trades log
      { id: 'holdings', label: 'Holdings', href: ROUTES.HOLDINGS, icon: 'holdings' },
      { id: 'funds', label: 'Funds', href: ROUTES.FUNDS, icon: 'funds' }
    ],
  },
  {
    section: NAV_SECTIONS.SYSTEM,
    items: [
      { id: 'logs', label: 'Logs', href: ROUTES.LOGS, icon: 'logs' },
      { id: 'alerts', label: 'Alerts', href: ROUTES.ALERTS, icon: 'alerts' },
      { id: 'scheduler', label: 'Scheduler', href: ROUTES.SCHEDULER, icon: 'scheduler' },
      { id: 'settings', label: 'Settings', href: ROUTES.SETTINGS, icon: 'settings' }
    ],
  },
]

// DEPENDENCY: These routes need backend endpoints before they can display real data:
// - /api/holdings → Holdings page
// - /api/funds → Funds page (balance, ledger, add/withdraw)
// - /api/reports → Reports & Performance pages
// - /api/logs → Logs page
// - /api/alerts → Alerts page (CRUD)
