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
  <div class="bg-gray-900 rounded-lg border border-gray-800">
    <!-- Header row -->
    <div class="flex items-center justify-between px-4 py-3 border-b border-gray-800">
      <h2 class="text-xs font-semibold text-gray-400 uppercase tracking-wide">
        Open Positions
        <span class="text-blue-400 ml-1">({{ positions.length }})</span>
      </h2>
      <div
        :class="[
          'flex items-center gap-1.5 text-xs font-medium px-2 py-1 rounded',
          isSafe ? 'text-emerald-400 bg-emerald-950' : 'text-red-400 bg-red-950'
        ]"
      >
        <span :class="['w-1.5 h-1.5 rounded-full', isSafe ? 'bg-emerald-400' : 'bg-red-400 animate-pulse']"></span>
        Circuit: {{ isSafe ? 'SAFE' : 'TRIPPED' }}
      </div>
    </div>

    <!-- Empty state -->
    <div v-if="positions.length === 0" class="text-center py-10 text-gray-700">
      No open positions
    </div>

    <!-- Table -->
    <table v-else class="w-full">
      <thead>
        <tr class="text-xs text-gray-600 uppercase border-b border-gray-800">
          <th class="text-left px-4 py-2 font-medium">Symbol</th>
          <th class="text-center px-3 py-2 font-medium">Side</th>
          <th class="text-right px-3 py-2 font-medium">Qty</th>
          <th class="text-right px-3 py-2 font-medium">Entry</th>
          <th class="text-right px-3 py-2 font-medium">LTP</th>
          <th class="text-right px-3 py-2 font-medium">P&amp;L</th>
          <th class="text-right px-3 py-2 font-medium">P&amp;L%</th>
          <th class="text-center px-3 py-2 font-medium">Dir</th>
          <th class="text-right px-4 py-2 font-medium">In Pos</th>
        </tr>
      </thead>
      <tbody>
        <tr
          v-for="pos in positions"
          :key="pos.id"
          class="border-b border-gray-800/60 hover:bg-gray-800/30 transition-colors"
        >
          <td class="px-4 py-3 font-medium text-gray-200">{{ pos.symbol }}</td>
          <td class="px-3 py-3 text-center">
            <span
              :class="[
                'text-xs font-bold px-1.5 py-0.5 rounded',
                pos.side === 'BUY' ? 'bg-blue-950 text-blue-400' : 'bg-orange-950 text-orange-400'
              ]"
            >{{ pos.side }}</span>
          </td>
          <td class="px-3 py-3 text-right text-gray-400 tabular-nums">{{ pos.quantity }}</td>
          <td class="px-3 py-3 text-right text-gray-500 tabular-nums">{{ inr(pos.entry_price) }}</td>
          <td class="px-3 py-3 text-right text-gray-300 font-semibold tabular-nums">{{ inr(pos.ltp) }}</td>
          <td :class="['px-3 py-3 text-right font-semibold tabular-nums', pnlClass(pos.pnl)]">
            {{ sign(pos.pnl) }}₹{{ inr(pos.pnl) }}
          </td>
          <td :class="['px-3 py-3 text-right tabular-nums', pnlClass(pos.pnl_pct)]">
            {{ sign(pos.pnl_pct) }}{{ inr(pos.pnl_pct) }}%
          </td>
          <td class="px-3 py-3 text-center text-gray-500">{{ dirIcon(pos.direction) }}</td>
          <td class="px-4 py-3 text-right text-gray-600 text-xs">{{ formatDuration(pos.time_in_position_sec) }}</td>
        </tr>
      </tbody>
    </table>
  </div>
</template>
