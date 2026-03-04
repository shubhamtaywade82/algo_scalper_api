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
  <div class="grid grid-cols-1 md:grid-cols-5 gap-4">
    <!-- Balance -->
    <div class="glass glass-hover rounded-xl p-5 relative overflow-hidden group">
      <div class="absolute top-0 right-0 w-24 h-24 bg-primary-500/5 rounded-full -mr-8 -mt-8 transition-transform group-hover:scale-150 duration-700"></div>
      <div class="text-[10px] text-gray-500 uppercase tracking-[0.15em] font-semibold mb-3">Total Balance</div>
      <div class="text-2xl font-bold text-white text-data">₹{{ inr(balance?.cash) }}</div>
      <div class="text-xs mt-2 flex items-center gap-1.5">
        <span class="text-gray-500">MTM:</span>
        <span :class="['font-medium text-data', pnlClass(balance?.mtm)]">
          {{ sign(balance?.mtm) }}₹{{ inr(balance?.mtm) }}
        </span>
      </div>
    </div>

    <!-- Today's P&L -->
    <div class="glass glass-hover rounded-xl p-5 relative overflow-hidden group">
      <div :class="['absolute top-0 right-0 w-24 h-24 rounded-full -mr-8 -mt-8 transition-transform group-hover:scale-150 duration-700 opacity-10', (stats?.total_pnl_rupees || 0) >= 0 ? 'bg-emerald-500' : 'bg-rose-500']"></div>
      <div class="text-[10px] text-gray-500 uppercase tracking-[0.15em] font-semibold mb-3">Today's P&amp;L</div>
      <div :class="['text-2xl font-bold text-data', pnlClass(stats?.total_pnl_rupees)]">
        {{ sign(stats?.total_pnl_rupees) }}₹{{ inr(stats?.total_pnl_rupees) }}
      </div>
      <div class="text-[10px] mt-2 flex gap-3 font-medium">
        <div class="flex items-center gap-1">
          <span class="text-gray-500">R:</span>
          <span :class="['text-data', pnlClass(stats?.realized_pnl_rupees)]">{{ sign(stats?.realized_pnl_rupees) }}₹{{ inr(stats?.realized_pnl_rupees) }}</span>
        </div>
        <div class="flex items-center gap-1">
          <span class="text-gray-500">U:</span>
          <span :class="['text-data', pnlClass(stats?.unrealized_pnl_rupees)]">{{ sign(stats?.unrealized_pnl_rupees) }}₹{{ inr(stats?.unrealized_pnl_rupees) }}</span>
        </div>
      </div>
    </div>

    <!-- Win Rate -->
    <div class="glass glass-hover rounded-xl p-5 relative overflow-hidden group">
      <div class="absolute top-0 right-0 w-24 h-24 bg-blue-500/5 rounded-full -mr-8 -mt-8 transition-transform group-hover:scale-150 duration-700"></div>
      <div class="text-[10px] text-gray-500 uppercase tracking-[0.15em] font-semibold mb-3">Performance</div>
      <div :class="['text-2xl font-bold text-data', (stats?.win_rate || 0) >= 50 ? 'text-emerald-400' : 'text-rose-400']">
        {{ stats?.win_rate ?? '—' }}<span class="text-sm font-normal ml-0.5">% WR</span>
      </div>
      <div class="text-[10px] text-gray-500 mt-2 font-medium">
        <span class="text-emerald-500/80">{{ stats?.winners ?? 0 }} Wins</span>
        <span class="mx-1.5 opacity-30">|</span>
        <span class="text-rose-500/80">{{ stats?.losers ?? 0 }} Losses</span>
      </div>
    </div>

    <!-- Active Positions -->
    <div class="glass glass-hover rounded-xl p-5 relative overflow-hidden group">
      <div class="absolute top-0 right-0 w-24 h-24 bg-blue-400/10 rounded-full -mr-8 -mt-8 transition-transform group-hover:scale-150 duration-700"></div>
      <div class="text-[10px] text-gray-500 uppercase tracking-[0.15em] font-semibold mb-3">Live Exposure</div>
      <div class="text-2xl font-bold text-blue-400 text-data flex items-baseline gap-1.5">
        {{ stats?.active_positions ?? 0 }}
        <span class="text-xs font-normal text-blue-500/60 uppercase tracking-widest">Active</span>
      </div>
    </div>

    <!-- Activity -->
    <div class="glass glass-hover rounded-xl p-5 relative overflow-hidden group">
      <div class="absolute top-0 right-0 w-24 h-24 bg-purple-500/5 rounded-full -mr-8 -mt-8 transition-transform group-hover:scale-150 duration-700"></div>
      <div class="text-[10px] text-gray-500 uppercase tracking-[0.15em] font-semibold mb-3">Trade Count</div>
      <div class="text-2xl font-bold text-gray-200 text-data flex items-baseline gap-1.5">
        {{ stats?.total_trades ?? 0 }}
        <span class="text-xs font-normal text-gray-500 uppercase tracking-widest">Trades</span>
      </div>
    </div>
  </div>
</template>
