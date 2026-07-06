export const endpoints = {
  dashboard: '/dashboard',
  settings: '/settings',
  settingsBulk: '/settings/bulk',
  settingsDeepMerge: '/settings/deep_merge',
  settingsFastEntryMode: '/settings/fast_entry_mode',
  settingsUpdateIP: '/settings/update_ip',

  candles: (symbol) => `/candles/${symbol}`,

  positions: '/positions',
  closePosition: (id) => `/positions/${id}/close`,

  signals: '/signals',

  scheduler: {
    tasks: '/scheduler/tasks',
    execute: (id) => `/scheduler/tasks/${id}/execute`
  },

  analysis: {
    show: (index) => `/analysis/${index}`,
    historical: (index) => `/analysis/${index}/historical`,
    riskExplorer: (index) => `/analysis/${index}/risk_explorer`,
    aiSnapshot: (index) => `/analysis/${index}/ai_snapshot`,
    optimize: (index) => `/analysis/${index}/optimize`
  },

  alpha: {
    status: '/alpha/status',
    history: '/alpha/history',
    performance: '/alpha/performance',
    scan: '/alpha/scan',
    execute: '/alpha/execute'
  },

  ledger: {
    balance: '/ledger/balance',
    journal: '/ledger/journal'
  },

  market: {
    depth: '/depth',
    vix: '/market/vix'
  },

  drawdownGuard: {
    reset: '/drawdown_guard/reset'
  },

  holdings: '/holdings',
  funds: '/funds',
  reports: {
    pnl: '/reports/pnl',
    trades: '/reports/trades',
    performance: '/reports/performance',
    export: '/reports/export'
  },
  alerts: '/alerts',
  logs: '/logs',
  equityCurve: '/equity_curve'
}
