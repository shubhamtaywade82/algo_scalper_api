<script setup>
import { computed } from 'vue'

const props = defineProps({
  positions: { type: Array, default: () => [] },
  circuitBreaker: Object
})

const isSafe = computed(() => !props.circuitBreaker?.tripped)

function inr(val, dec = 2) {
  if (val == null) return '—'
  return Math.abs(Number(val)).toLocaleString('en-IN', {
    minimumFractionDigits: dec,
    maximumFractionDigits: dec
  })
}

function pnlClass(val) {
  const n = Number(val)
  if (!n) return 'text-gray-500'
  return n > 0 ? 'text-emerald-400' : 'text-red-400'
}

function sign(val) {
  const n = Number(val)
  return n > 0 ? '+' : n < 0 ? '−' : ''
}

function formatDuration(secs) {
  if (!secs) return '—'
  const m = Math.floor(secs / 60)
  const s = Math.floor(secs % 60)
  return m > 0 ? `${m}m ${s}s` : `${s}s`
}

function dirIcon(dir) {
  if (!dir) return ''
  return dir.toLowerCase().includes('bull') ? '↑' : '↓'
}
</script>

<template>
  <div class="glass rounded-2xl overflow-hidden mt-6">
    <!-- Header row -->
    <div class="flex items-center justify-between px-6 py-4 border-b border-white/5 bg-white/[0.02]">
      <div class="flex items-center gap-3">
        <div class="w-2 h-8 bg-primary-500 rounded-full"></div>
        <h2 class="text-sm font-bold text-white uppercase tracking-[0.2em]">
          Open Positions
          <span class="text-primary-400 ml-2 font-black text-data">[{{ positions.length }}]</span>
        </h2>
      </div>
      <div
        :class="[
          'flex items-center gap-2 text-[10px] font-black tracking-widest px-3 py-1.5 rounded-full transition-all duration-500 border',
          isSafe ? 'text-emerald-400 bg-emerald-500/10 border-emerald-500/20' : 'text-rose-400 bg-rose-500/10 border-rose-500/20'
        ]"
      >
        <span :class="['w-2 h-2 rounded-full', isSafe ? 'bg-emerald-400 shadow-[0_0_8px_oklch(0.64_0.17_145_/_0.5)]' : 'bg-rose-400 animate-pulse shadow-[0_0_12px_oklch(0.62_0.18_20_/_0.5)]']"></span>
        CIRCUIT: {{ isSafe ? 'OPTIMAL' : 'TRIPPED' }}
      </div>
    </div>

    <!-- Empty state -->
    <div v-if="positions.length === 0" class="flex flex-col items-center justify-center py-20 text-gray-600">
      <div class="w-16 h-16 rounded-full bg-white/5 flex items-center justify-center mb-4">
        <span class="text-2xl">⚡</span>
      </div>
      <p class="text-xs uppercase tracking-widest font-bold">Scanning for entries...</p>
    </div>

    <!-- Table Container -->
    <div v-else class="overflow-x-auto">
      <table class="w-full border-collapse">
        <thead>
          <tr class="text-[10px] text-gray-500 uppercase tracking-widest border-b border-white/5 bg-white/[0.01]">
            <th class="text-left px-6 py-4 font-bold">Asset</th>
            <th class="text-center px-4 py-4 font-bold">Position</th>
            <th class="text-right px-4 py-4 font-bold">Size</th>
            <th class="text-right px-4 py-4 font-bold">Entry</th>
            <th class="text-right px-4 py-4 font-bold">Current</th>
            <th class="text-right px-4 py-4 font-bold">Net P&amp;L</th>
            <th class="text-right px-4 py-4 font-bold">% Change</th>
            <th class="text-center px-4 py-4 font-bold">Trend</th>
            <th class="text-right px-6 py-4 font-bold">Duration</th>
          </tr>
        </thead>
        <tbody class="divide-y divide-white/5">
          <tr
            v-for="pos in positions"
            :key="pos.id"
            class="group hover:bg-white/[0.03] transition-all duration-300 relative"
          >
            <td class="px-6 py-5">
              <div class="flex flex-col">
                <span class="text-sm font-bold text-gray-100 uppercase tracking-tight">{{ pos.symbol }}</span>
                <span class="text-[9px] text-gray-600 font-bold uppercase tracking-widest mt-0.5">Dhan Equity</span>
              </div>
            </td>
            <td class="px-4 py-5 text-center">
              <span
                :class="[
                  'text-[10px] font-black px-2.5 py-1 rounded-md tracking-tighter inline-block min-w-[50px]',
                  pos.side === 'BUY' ? 'bg-emerald-500/10 text-emerald-400 border border-emerald-500/20' : 'bg-rose-500/10 text-rose-400 border border-rose-500/20'
                ]"
              >{{ pos.side }}</span>
            </td>
            <td class="px-4 py-5 text-right text-gray-400 text-data font-medium">{{ pos.quantity }}</td>
            <td class="px-4 py-5 text-right text-gray-500 text-data text-xs">{{ inr(pos.entry_price) }}</td>
            <td class="px-4 py-5 text-right text-white font-black text-data scale-105 transition-transform group-hover:scale-110 shadow-emerald-500/20">{{ inr(pos.ltp) }}</td>
            <td :class="['px-4 py-5 text-right font-black text-data text-sm', pnlClass(pos.pnl)]">
              {{ sign(pos.pnl) }}₹{{ inr(pos.pnl) }}
            </td>
            <td :class="['px-4 py-5 text-right text-data font-bold', pnlClass(pos.pnl_pct)]">
              <div class="flex items-center justify-end gap-1">
                <span>{{ sign(pos.pnl_pct) }}{{ inr(pos.pnl_pct) }}%</span>
                <div :class="['w-1 h-3 rounded-full', Number(pos.pnl_pct) >= 0 ? 'bg-emerald-500' : 'bg-rose-500']"></div>
              </div>
            </td>
            <td class="px-4 py-5 text-center">
              <span :class="['text-sm transition-transform duration-500 group-hover:scale-125 inline-block', Number(pos.pnl_pct) >= 0 ? 'text-emerald-400' : 'text-rose-400']">
                {{ dirIcon(pos.direction) }}
              </span>
            </td>
            <td class="px-6 py-5 text-right">
              <div class="flex flex-col items-end">
                <span class="text-data text-[11px] text-gray-400 font-bold">{{ formatDuration(pos.time_in_position_sec) }}</span>
                <div class="w-12 h-1 bg-white/5 rounded-full mt-1.5 overflow-hidden">
                  <div class="h-full bg-primary-500/40 animate-pulse" :style="{ width: '60%' }"></div>
                </div>
              </div>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
  </div>
</template>
