export const endpoints = {
  dashboard: '/dashboard',
  // GET reads; PUT replaces whole sections ({ settings }); PATCH deep-merges ({ patch })
  settings: '/settings',
  settingsFastEntryMode: '/settings/fast_entry_mode',
  settingsIpWhitelist: '/settings/ip_whitelist',

  candles: (symbol) => `/candles/${symbol}`,

  positions: '/positions',
  positionDetail: (id) => `/positions/${id}`,
  positionClosure: (id) => `/positions/${id}/closure`,

  signals: '/signals',

  scheduler: {
    tasks: '/scheduler/tasks',
    executions: (taskId) => `/scheduler/tasks/${taskId}/executions`
  },

  analysis: {
    show: (index) => `/analysis/${index}`,
    history: (index) => `/analysis/${index}/history`,
    aiSnapshots: (index) => `/analysis/${index}/ai_snapshots`
  },

  alpha: {
    status: '/alpha/status',
    history: '/alpha/history',
    performance: '/alpha/performance'
  },

  ledger: {
    balance: '/ledger/balance',
    journal: '/ledger/journal'
  },

  market: {
    depth: '/depth',
    vix: '/market/vix'
  },

  // DELETE clears the day's latched drawdown trip (operator token)
  drawdownGuardTrip: '/drawdown_guard/trip',

  holdings: '/holdings',
  funds: '/funds',
  fundDeposits: '/funds/deposits',
  fundWithdrawals: '/funds/withdrawals',
  reports: {
    pnl: '/reports/pnl',
    trades: '/reports/trades',
    performance: '/reports/performance',
    export: '/reports/export',
    pnlByStrategy: '/reports/pnl_by_strategy',
    pnlByInstrument: '/reports/pnl_by_instrument',
    marketBrief: '/reports/market_brief',
    marketBriefLive: '/reports/market_brief/live'
  },
  orders: '/orders',
  alerts: '/alerts',
  logs: '/logs',
  equityCurve: '/equity_curve',

  strategies: {
    list: '/strategies',
    one: (slug) => `/strategies/${slug}`
  },
  tradingStrategies: {
    list: '/trading_strategies',
    one: (id) => `/trading_strategies/${id}`,
    validation: (id) => `/trading_strategies/${id}/validation`,
    deployment: (id) => `/trading_strategies/${id}/deployment`
  }
}
