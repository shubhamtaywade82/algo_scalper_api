<script setup>
import { computed } from 'vue'
import { useFlash } from '../composables/useFlash'

const props = defineProps({
  stats: {
    type: Object,
    default: () => ({
      total_trades: 0,
      active_positions: 0,
      total_pnl_rupees: 0,
      realized_pnl_rupees: 0,
      unrealized_pnl_rupees: 0,
      win_rate: 0,
      winners: 0,
      losers: 0
    })
  },
  balance: {
    type: Object,
    default: () => ({
      cash: 0,
      equity: 0,
      mtm: 0,
      exposure: 0
    })
  }
})

const totalPnlRef = computed(() => props.stats?.total_pnl_rupees)
const realizedPnlRef = computed(() => props.stats?.realized_pnl_rupees)
const unrealizedPnlRef = computed(() => props.stats?.unrealized_pnl_rupees)
const cashRef = computed(() => props.balance?.cash)

const { flashClass: totalFlash } = useFlash(totalPnlRef)
const { flashClass: realizedFlash } = useFlash(realizedPnlRef)
const { flashClass: unrealizedFlash } = useFlash(unrealizedPnlRef)
const { flashClass: cashFlash } = useFlash(cashRef)

function inr(val) {
  if (val == null) return '0.00'
  return Math.abs(Number(val)).toLocaleString('en-IN', {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2
  })
}

function pnlClass(val) {
  const n = Number(val)
  if (!n) return 'from-gray-400 to-gray-500'
  return n >= 0 ? 'from-emerald-400 to-emerald-500' : 'from-rose-400 to-rose-500'
}

function sign(val) {
  return Number(val) >= 0 ? '+' : '−'
}
</script>

<template>
  <div class="grid grid-cols-1 md:grid-cols-3 xl:grid-cols-6 gap-4">
    <!-- Available Balance Card -->
    <div class="glass glass-hover p-5 rounded-2xl relative overflow-hidden group border-l-4 border-primary-500/50">
      <div class="absolute top-0 right-0 w-32 h-32 bg-primary-500/5 blur-3xl transition-opacity group-hover:opacity-10"></div>
      <div class="flex flex-col relative z-10">
        <span class="text-[10px] font-black text-gray-500 uppercase tracking-widest mb-1">Available Cash</span>
        <div :class="['flex items-baseline gap-1 mt-1 transition-all duration-300 rounded-lg px-2 -ml-2', cashFlash]">
          <span class="text-2xl font-black text-white text-data tracking-tight">₹{{ inr(balance?.cash) }}</span>
        </div>
        <div class="flex items-center gap-2 mt-4">
          <span class="text-[9px] font-black text-primary-400 uppercase tracking-widest">MARGIN READY</span>
          <div class="w-1.5 h-1.5 rounded-full bg-primary-500 animate-pulse"></div>
        </div>
      </div>
    </div>

    <!-- Total P&L Card -->
    <div class="glass glass-hover p-5 rounded-2xl relative overflow-hidden group">
      <div :class="['absolute top-0 right-0 w-32 h-32 bg-gradient-to-br opacity-5 blur-3xl transition-opacity group-hover:opacity-10', pnlClass(stats.total_pnl_rupees)]"></div>
      <div class="flex flex-col relative z-10">
        <span class="text-[10px] font-black text-gray-500 uppercase tracking-widest mb-1">Total Net P&amp;L</span>
        <div :class="['flex items-baseline gap-1 mt-1 transition-all duration-300 rounded-lg px-2 -ml-2', totalFlash]">
          <span :class="['text-sm font-bold', Number(stats.total_pnl_rupees) >= 0 ? 'text-emerald-400' : 'text-rose-400']">{{ sign(stats.total_pnl_rupees) }}</span>
          <span class="text-3xl font-black text-white text-data tracking-tighter">₹{{ inr(stats.total_pnl_rupees) }}</span>
        </div>
        <div class="flex items-center gap-2 mt-4">
          <div class="flex -space-x-2">
            <div class="w-6 h-6 rounded-full bg-emerald-500/10 border border-emerald-500/20 flex items-center justify-center text-[10px] font-bold text-emerald-400">{{ stats.winners }}</div>
            <div class="w-6 h-6 rounded-full bg-rose-500/10 border border-rose-500/20 flex items-center justify-center text-[10px] font-bold text-rose-400">{{ stats.losers }}</div>
          </div>
          <span class="text-[10px] font-bold text-gray-600 uppercase tracking-tighter">Day Performance</span>
        </div>
      </div>
    </div>

    <!-- Realized P&L -->
    <div class="glass glass-hover p-5 rounded-2xl relative overflow-hidden group">
      <div :class="['absolute top-0 right-0 w-32 h-32 bg-gradient-to-br opacity-5 blur-3xl transition-opacity group-hover:opacity-10', pnlClass(stats.realized_pnl_rupees)]"></div>
      <div class="flex flex-col relative z-10">
        <span class="text-[10px] font-black text-gray-500 uppercase tracking-widest mb-1">Realized</span>
        <div :class="['flex items-baseline gap-1 mt-1 transition-all duration-300 rounded-lg px-2 -ml-2', realizedFlash]">
          <span :class="['text-xs font-bold', Number(stats.realized_pnl_rupees) >= 0 ? 'text-emerald-400' : 'text-rose-400']">{{ sign(stats.realized_pnl_rupees) }}</span>
          <span class="text-2xl font-black text-white text-data tracking-tight">₹{{ inr(stats.realized_pnl_rupees) }}</span>
        </div>
        <div class="w-full bg-white/5 h-1 rounded-full mt-5 overflow-hidden">
          <div class="h-full bg-primary-500/30 w-full animate-pulse"></div>
        </div>
      </div>
    </div>

    <!-- Unrealized P&L -->
    <div class="glass glass-hover p-5 rounded-2xl relative overflow-hidden group border-l-4" :style="{ borderLeftColor: `var(--color-${Number(stats.unrealized_pnl_rupees) >= 0 ? 'emerald' : 'rose'}-500)` }">
      <div :class="['absolute top-0 right-0 w-32 h-32 bg-gradient-to-br opacity-5 blur-3xl transition-opacity group-hover:opacity-10', pnlClass(stats.unrealized_pnl_rupees)]"></div>
      <div class="flex flex-col relative z-10">
        <span class="text-[10px] font-black text-gray-500 uppercase tracking-widest mb-1">Active Unrealized</span>
        <div :class="['flex items-baseline gap-1 mt-1 transition-all duration-300 rounded-lg px-2 -ml-2', unrealizedFlash]">
          <span :class="['text-xs font-bold', Number(stats.unrealized_pnl_rupees) >= 0 ? 'text-emerald-400' : 'text-rose-400']">{{ sign(stats.unrealized_pnl_rupees) }}</span>
          <span class="text-2xl font-black text-white text-data tracking-tight">₹{{ inr(stats.unrealized_pnl_rupees) }}</span>
        </div>
        <div class="flex items-center gap-2 mt-4">
          <span class="text-[9px] font-black text-primary-400 uppercase tracking-widest">LIVE TRACKING</span>
          <span class="relative flex h-2 w-2">
            <span class="animate-ping absolute inline-flex h-full w-full rounded-full bg-primary-400 opacity-75"></span>
            <span class="relative inline-flex rounded-full h-2 w-2 bg-primary-500"></span>
          </span>
        </div>
      </div>
    </div>

    <!-- Active Positions -->
    <div class="glass glass-hover p-5 rounded-2xl relative overflow-hidden group">
      <div class="absolute top-0 right-0 w-24 h-24 bg-primary-400/10 rounded-full -mr-8 -mt-8 transition-transform group-hover:scale-150 duration-700"></div>
      <div class="flex flex-col relative z-10">
        <span class="text-[10px] font-black text-gray-500 uppercase tracking-widest mb-1">Live Exposure</span>
        <div class="flex items-baseline gap-2 mt-2">
          <span class="text-3xl font-black text-primary-400 text-data">{{ stats?.active_positions ?? 0 }}</span>
          <span class="text-[10px] font-bold text-gray-500 uppercase tracking-widest">Active</span>
        </div>
        <div class="flex items-center gap-1 mt-4">
          <div class="w-1 h-3 bg-primary-500/40 rounded-full"></div>
          <div class="w-1 h-3 bg-primary-500/20 rounded-full"></div>
          <div class="w-1 h-3 bg-primary-500/10 rounded-full"></div>
        </div>
      </div>
    </div>

    <!-- Activity -->
    <div class="glass glass-hover p-5 rounded-2xl relative overflow-hidden group">
      <div class="absolute top-0 right-0 w-24 h-24 bg-white/5 rounded-full -mr-8 -mt-8 transition-transform group-hover:scale-150 duration-700"></div>
      <div class="flex flex-col relative z-10">
        <span class="text-[10px] font-black text-gray-500 uppercase tracking-widest mb-1">Day Volume</span>
        <div class="flex items-baseline gap-2 mt-2">
          <span class="text-3xl font-black text-white text-data">{{ stats?.total_trades ?? 0 }}</span>
          <span class="text-[10px] font-bold text-gray-500 uppercase tracking-widest">Trades</span>
        </div>
        <div class="mt-4 flex items-center gap-1">
          <div v-for="i in 5" :key="i" :class="['h-1 flex-1 rounded-full', i <= 3 ? 'bg-primary-500/40' : 'bg-white/5']"></div>
        </div>
      </div>
    </div>
  </div>
</template>
