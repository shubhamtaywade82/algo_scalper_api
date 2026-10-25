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
  PORTFOLIO: '/portfolio',
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
  STRATEGIES: { id: 'strategies', label: 'Strategies' },
  PORTFOLIO: { id: 'portfolio', label: 'Portfolio' },
  SYSTEM: { id: 'system', label: 'System' },
}

export const navigationConfig = [
  {
    section: NAV_SECTIONS.MAIN,
    items: [
      { id: 'dashboard', label: 'Dashboard', href: ROUTES.DASHBOARD, icon: 'dashboard', end: true },
      { id: 'reports', label: 'Reports', href: ROUTES.REPORTS, icon: 'reports' }
    ],
  },
  {
    section: NAV_SECTIONS.MARKET,
    items: [
      { id: 'option-chain', label: 'Option Chain', href: ROUTES.OPTION_CHAIN, icon: 'optionChain' },
      { id: 'market-watch', label: 'Market Watch', href: ROUTES.MARKET_WATCH, icon: 'marketWatch' },
      { id: 'analysis', label: 'Analysis', href: ROUTES.ANALYSIS, icon: 'analysis' },
      { id: 'market-data', label: 'Market Data', href: ROUTES.CHARTS, icon: 'charts' }
    ],
  },
  {
    section: NAV_SECTIONS.STRATEGIES,
    items: [
      { id: 'strategies', label: 'Strategies', href: ROUTES.STRATEGIES, icon: 'strategies' },
      { id: 'signals', label: 'Signals', href: ROUTES.SIGNALS, icon: 'signals' }
    ],
  },
  {
    section: NAV_SECTIONS.PORTFOLIO,
    items: [
      { id: 'portfolio', label: 'Portfolio', href: ROUTES.PORTFOLIO, icon: 'portfolio' }
    ],
  },
  {
    section: NAV_SECTIONS.SYSTEM,
    items: [
      { id: 'settings', label: 'Settings', href: ROUTES.SETTINGS, icon: 'settings' }
    ],
  },
]

// Backend DEPENDENCY (not yet implemented):
// - /api/replay → Replay historical data ingestion and player control state
