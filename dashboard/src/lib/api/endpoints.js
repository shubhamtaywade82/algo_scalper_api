export const endpoints = {
  dashboard: '/dashboard',
  settings: '/settings',
  settingsBulk: '/settings/bulk',
  settingsDeepMerge: '/settings/deep_merge',
  settingsFastEntryMode: '/settings/fast_entry_mode',
  settingsUpdateIP: '/settings/update_ip',

  candles: (symbol) => `/candles/${symbol}`,

  positions: '/positions',
  positionDetail: (id) => `/positions/${id}`,
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
    export: '/reports/export',
    pnlByStrategy: '/reports/pnl_by_strategy',
    pnlByInstrument: '/reports/pnl_by_instrument'
  },
  orders: '/orders',
  alerts: '/alerts',
  logs: '/logs',
  equityCurve: '/equity_curve',

  strategies: {
    list: '/strategies',
    one: (id) => `/strategies/${id}`
  },
  tradingStrategies: {
    list: '/trading_strategies',
    one: (id) => `/trading_strategies/${id}`,
    validate: (id) => `/trading_strategies/${id}/validate`,
    deploy: (id) => `/trading_strategies/${id}/deploy`
  }
}

