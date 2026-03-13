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
  if (r.includes('time') || r.includes('eod')) return { label: 'TIME', cls: 'text-yellow-400' }
  if (r.includes('tp') || r.includes('target') || r.includes('profit')) return { label: 'TP', cls: 'text-emerald-400' }
  if (r.includes('trail')) return { label: 'TRAIL', cls: 'text-blue-400' }
  if (r.includes('manual')) return { label: 'MNL', cls: 'text-purple-400' }
  return { label: reason.slice(0, 8).toUpperCase(), cls: 'text-gray-400' }
}
</script>

<template>
  <div class="glass rounded-2xl overflow-hidden mt-8 opacity-90 transition-opacity hover:opacity-100">
    <div class="flex items-center justify-between px-6 py-4 border-b border-white/5 bg-white/[0.01]">
      <div class="flex items-center gap-3">
        <div class="w-1.5 h-6 bg-gray-600 rounded-full"></div>
        <h2 class="text-xs font-bold text-gray-400 uppercase tracking-[0.2em]">
          Completed Trades
          <span class="text-gray-600 ml-2 font-black text-data">[{{ positions.length }}]</span>
        </h2>
      </div>
    </div>

    <div v-if="positions.length === 0" class="flex flex-col items-center justify-center py-16 text-gray-700">
      <p class="text-[10px] uppercase tracking-widest font-bold">No closed trades recorded yet</p>
    </div>

    <div v-else class="overflow-x-auto">
      <table class="w-full border-collapse">
        <thead>
          <tr class="text-[9px] text-gray-600 uppercase tracking-widest border-b border-white/5 bg-white/[0.005]">
            <th class="text-left px-6 py-3 font-bold">Asset</th>
            <th class="text-center px-4 py-3 font-bold">Side</th>
            <th class="text-right px-4 py-3 font-bold">Qty</th>
            <th class="text-right px-4 py-3 font-bold">Entry</th>
            <th class="text-right px-4 py-3 font-bold">Exit</th>
            <th class="text-right px-4 py-3 font-bold">Net P&amp;L</th>
            <th class="text-right px-4 py-3 font-bold">% P/L</th>
            <th class="text-center px-4 py-3 font-bold">Source</th>
            <th class="text-right px-6 py-3 font-bold">Time</th>
          </tr>
        </thead>
        <tbody class="divide-y divide-white/5">
          <tr
            v-for="pos in positions"
            :key="pos.id"
            class="group hover:bg-white/[0.02] transition-colors"
          >
            <td class="px-6 py-4">
              <span class="text-xs font-bold text-gray-500 uppercase tracking-tight group-hover:text-gray-300 transition-colors">{{ pos.symbol }}</span>
            </td>
            <td class="px-4 py-4 text-center">
              <span
                :class="[
                  'text-[9px] font-black px-2 py-0.5 rounded tracking-tighter uppercase inline-block min-w-[40px] opacity-70 group-hover:opacity-100 transition-opacity',
                  pos.side === 'BUY' ? 'bg-primary-900/30 text-primary-400 border border-primary-500/20' : 'bg-rose-900/30 text-rose-400 border border-rose-500/20'
                ]"
              >{{ pos.side }}</span>
            </td>
            <td class="px-4 py-4 text-right text-gray-600 text-data text-xs">{{ pos.quantity }}</td>
            <td class="px-4 py-4 text-right text-gray-600 text-data text-xs">{{ inr(pos.entry_price) }}</td>
            <td class="px-4 py-4 text-right text-gray-500 text-data text-xs">{{ inr(pos.exit_price) }}</td>
            <td :class="['px-4 py-4 text-right font-bold text-data text-xs', pnlClass(pos.pnl)]">
              {{ sign(pos.pnl) }}₹{{ inr(pos.pnl) }}
            </td>
            <td :class="['px-4 py-4 text-right text-data font-medium text-xs', pnlClass(pos.pnl_pct)]">
              {{ sign(pos.pnl_pct) }}{{ inr(pos.pnl_pct) }}%
            </td>
            <td class="px-4 py-4 text-center">
              <span :class="['text-[9px] font-black px-1.5 py-0.5 rounded border tracking-widest', exitBadge(pos.exit_reason).cls + '/20 border-' + exitBadge(pos.exit_reason).cls + '/10']">
                {{ exitBadge(pos.exit_reason).label }}
              </span>
            </td>
            <td class="px-6 py-4 text-right text-gray-600 text-data text-[10px]">{{ formatTime(pos.exited_at) }}</td>
          </tr>
        </tbody>
      </table>
    </div>
  </div>
</template>
