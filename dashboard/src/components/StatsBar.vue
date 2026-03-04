<script setup>
defineProps({
  balance: Object,
  stats: Object
})

function inr(val, dec = 2) {
  if (val == null) return '—'
  return Math.abs(Number(val)).toLocaleString('en-IN', {
    minimumFractionDigits: dec,
    maximumFractionDigits: dec
  })
}

function pnlClass(val) {
  if (!val) return 'text-gray-400'
  return Number(val) > 0 ? 'text-emerald-400' : Number(val) < 0 ? 'text-red-400' : 'text-gray-400'
}

function sign(val) {
  const n = Number(val)
  return n > 0 ? '+' : n < 0 ? '−' : ''
}
</script>

<template>
  <div class="grid grid-cols-5 gap-3">
    <!-- Balance -->
    <div class="bg-gray-900 rounded-lg p-4 border border-gray-800">
      <div class="text-xs text-gray-600 uppercase tracking-wide mb-2">Balance</div>
      <div class="text-xl font-bold text-white tabular-nums">₹{{ inr(balance?.cash) }}</div>
      <div class="text-xs text-gray-600 mt-1">
        MTM:
        <span :class="pnlClass(balance?.mtm)">
          {{ sign(balance?.mtm) }}₹{{ inr(balance?.mtm) }}
        </span>
      </div>
    </div>

    <!-- Total PnL -->
    <div class="bg-gray-900 rounded-lg p-4 border border-gray-800">
      <div class="text-xs text-gray-600 uppercase tracking-wide mb-2">Today's P&amp;L</div>
      <div :class="['text-xl font-bold tabular-nums', pnlClass(stats?.total_pnl_rupees)]">
        {{ sign(stats?.total_pnl_rupees) }}₹{{ inr(stats?.total_pnl_rupees) }}
      </div>
      <div class="text-xs text-gray-600 mt-1 flex gap-2">
        <span>R: <span :class="pnlClass(stats?.realized_pnl_rupees)">{{ sign(stats?.realized_pnl_rupees) }}₹{{ inr(stats?.realized_pnl_rupees) }}</span></span>
        <span>U: <span :class="pnlClass(stats?.unrealized_pnl_rupees)">{{ sign(stats?.unrealized_pnl_rupees) }}₹{{ inr(stats?.unrealized_pnl_rupees) }}</span></span>
      </div>
    </div>

    <!-- Win Rate -->
    <div class="bg-gray-900 rounded-lg p-4 border border-gray-800">
      <div class="text-xs text-gray-600 uppercase tracking-wide mb-2">Win Rate</div>
      <div :class="['text-xl font-bold', (stats?.win_rate || 0) >= 50 ? 'text-emerald-400' : 'text-red-400']">
        {{ stats?.win_rate ?? '—' }}%
      </div>
      <div class="text-xs text-gray-600 mt-1">
        W:{{ stats?.winners ?? 0 }} &nbsp; L:{{ stats?.losers ?? 0 }}
      </div>
    </div>

    <!-- Open Positions -->
    <div class="bg-gray-900 rounded-lg p-4 border border-gray-800">
      <div class="text-xs text-gray-600 uppercase tracking-wide mb-2">Open Positions</div>
      <div class="text-xl font-bold text-blue-400">{{ stats?.active_positions ?? 0 }}</div>
    </div>

    <!-- Closed Today -->
    <div class="bg-gray-900 rounded-lg p-4 border border-gray-800">
      <div class="text-xs text-gray-600 uppercase tracking-wide mb-2">Closed Today</div>
      <div class="text-xl font-bold text-gray-300">{{ stats?.total_trades ?? 0 }}</div>
    </div>
  </div>
</template>
