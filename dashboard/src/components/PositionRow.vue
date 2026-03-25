<script setup>
import { computed, toRef } from 'vue'
import { useFlash } from '../composables/useFlash'

const props = defineProps({
  pos: Object
})

const ltpRef = toRef(props.pos, 'ltp')
const pnlRef = toRef(props.pos, 'pnl')
const isStale = computed(() => props.pos?.stale === true)

const { flashClass: ltpFlash } = useFlash(ltpRef)
const { flashClass: pnlFlash } = useFlash(pnlRef)

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
  return n > 0 ? 'text-emerald-400' : 'text-rose-400'
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
  <tr class="group hover:bg-white/[0.03] transition-all duration-300 relative">
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
    <td
      :class="[
        'px-4 py-5 text-right text-white font-black text-data transition-all duration-300 rounded-lg',
        isStale ? 'bg-amber-500/10 text-amber-300 border border-amber-500/20' : ltpFlash
      ]"
    >
      <div class="flex items-center justify-end gap-2">
        <span>{{ inr(pos.ltp) }}</span>
        <span
          v-if="isStale"
          class="text-[9px] font-black text-amber-300 bg-amber-500/10 border border-amber-500/20 px-2 py-0.5 rounded-md"
        >
          STALE
        </span>
      </div>
    </td>
    <td :class="['px-4 py-5 text-right font-black text-data text-sm transition-all duration-300 rounded-lg', pnlClass(pos.pnl), pnlFlash]">
      {{ sign(pos.pnl) }}₹{{ inr(pos.pnl) }}
    </td>
    <td :class="['px-4 py-5 text-right text-data font-bold', pnlClass(pos.pnl_pct)]">
      <div class="flex items-center justify-end gap-1">
        <span>{{ sign(pos.pnl_pct) }}{{ inr(pos.pnl_pct) }}%</span>
        <div :class="['w-1 h-3 rounded-full', Number(pos.pnl_pct) >= 0 ? 'bg-emerald-500' : 'bg-rose-500']"></div>
      </div>
    </td>
    <td class="px-4 py-5 text-right font-black text-amber-400 text-data text-xs">
      ₹{{ inr(pos.hwm_pnl) }}
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
</template>
