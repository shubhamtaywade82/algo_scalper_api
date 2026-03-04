<script setup>
defineProps({
  positions: { type: Array, default: () => [] }
})

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

function formatTime(iso) {
  if (!iso) return '—'
  try {
    return new Date(iso).toLocaleTimeString('en-IN', {
      hour: '2-digit',
      minute: '2-digit',
      hour12: false
    })
  } catch {
    return '—'
  }
}

function exitBadge(reason) {
  if (!reason) return { label: '—', cls: 'text-gray-600' }
  const r = reason.toLowerCase()
  if (r.includes('sl') || r.includes('stop_loss')) return { label: 'SL', cls: 'text-red-400' }
  if (r.includes('tp') || r.includes('target') || r.includes('profit')) return { label: 'TP', cls: 'text-emerald-400' }
  if (r.includes('trail')) return { label: 'TRAIL', cls: 'text-blue-400' }
  if (r.includes('time') || r.includes('eod')) return { label: 'TIME', cls: 'text-yellow-400' }
  if (r.includes('manual')) return { label: 'MNL', cls: 'text-purple-400' }
  return { label: reason.slice(0, 8).toUpperCase(), cls: 'text-gray-400' }
}
</script>

<template>
  <div class="bg-gray-900 rounded-lg border border-gray-800">
    <div class="px-4 py-3 border-b border-gray-800">
      <h2 class="text-xs font-semibold text-gray-400 uppercase tracking-wide">
        Today's Trades
        <span class="text-gray-600 ml-1">({{ positions.length }})</span>
      </h2>
    </div>

    <div v-if="positions.length === 0" class="text-center py-10 text-gray-700">
      No closed trades today
    </div>

    <table v-else class="w-full">
      <thead>
        <tr class="text-xs text-gray-600 uppercase border-b border-gray-800">
          <th class="text-left px-4 py-2 font-medium">Symbol</th>
          <th class="text-center px-3 py-2 font-medium">Side</th>
          <th class="text-right px-3 py-2 font-medium">Qty</th>
          <th class="text-right px-3 py-2 font-medium">Entry</th>
          <th class="text-right px-3 py-2 font-medium">Exit</th>
          <th class="text-right px-3 py-2 font-medium">P&amp;L</th>
          <th class="text-right px-3 py-2 font-medium">P&amp;L%</th>
          <th class="text-center px-3 py-2 font-medium">Reason</th>
          <th class="text-right px-4 py-2 font-medium">Time</th>
        </tr>
      </thead>
      <tbody>
        <tr
          v-for="pos in positions"
          :key="pos.id"
          class="border-b border-gray-800/60 hover:bg-gray-800/30 transition-colors opacity-80"
        >
          <td class="px-4 py-3 text-gray-400">{{ pos.symbol }}</td>
          <td class="px-3 py-3 text-center">
            <span
              :class="[
                'text-xs font-bold px-1.5 py-0.5 rounded',
                pos.side === 'BUY' ? 'bg-blue-950/60 text-blue-500' : 'bg-orange-950/60 text-orange-500'
              ]"
            >{{ pos.side }}</span>
          </td>
          <td class="px-3 py-3 text-right text-gray-600 tabular-nums">{{ pos.quantity }}</td>
          <td class="px-3 py-3 text-right text-gray-600 tabular-nums">{{ inr(pos.entry_price) }}</td>
          <td class="px-3 py-3 text-right text-gray-500 tabular-nums">{{ inr(pos.exit_price) }}</td>
          <td :class="['px-3 py-3 text-right font-semibold tabular-nums', pnlClass(pos.pnl)]">
            {{ sign(pos.pnl) }}₹{{ inr(pos.pnl) }}
          </td>
          <td :class="['px-3 py-3 text-right tabular-nums', pnlClass(pos.pnl_pct)]">
            {{ sign(pos.pnl_pct) }}{{ inr(pos.pnl_pct) }}%
          </td>
          <td class="px-3 py-3 text-center">
            <span :class="['text-xs font-bold', exitBadge(pos.exit_reason).cls]">
              {{ exitBadge(pos.exit_reason).label }}
            </span>
          </td>
          <td class="px-4 py-3 text-right text-gray-600 text-xs">{{ formatTime(pos.exited_at) }}</td>
        </tr>
      </tbody>
    </table>
  </div>
</template>
