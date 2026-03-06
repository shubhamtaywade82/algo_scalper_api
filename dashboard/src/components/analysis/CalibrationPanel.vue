<script setup>
import { computed } from 'vue'

const props = defineProps({ data: Object })

const calibration = computed(() => props.data?.calibration)

function fmt(v, dec = 1) {
  if (v == null) return '—'
  return Number(v).toFixed(dec)
}

function fmtPct(v) {
  if (v == null) return '—'
  return `${v >= 0 ? '+' : ''}${Number(v).toFixed(2)}%`
}
</script>

<template>
  <div v-if="calibration" class="glass rounded-2xl p-6 glass-hover">
    <div class="flex items-center gap-3 mb-5">
      <span class="text-[10px] font-black text-gray-500 tracking-[0.2em] uppercase">🎯 Trailing Stop Calibration</span>
    </div>

    <div class="grid grid-cols-1 lg:grid-cols-2 gap-4">
      <!-- CE Calibration -->
      <div v-if="calibration.ce" class="rounded-xl p-5 bg-white/[0.02] border-l-[3px] border-l-emerald-400">
        <div class="text-[10px] font-black text-emerald-400 tracking-widest uppercase mb-3">CE (Call) ATM</div>
        <div class="space-y-3">
          <div class="flex items-center justify-between">
            <span class="text-[9px] font-bold text-gray-500 tracking-wider">Avg Max Gain</span>
            <span class="text-data text-sm font-black text-emerald-400">{{ fmtPct(calibration.ce.avg_max_gain_pct) }}</span>
          </div>
          <div class="flex items-center justify-between">
            <span class="text-[9px] font-bold text-gray-500 tracking-wider">Avg Retrace</span>
            <span class="text-data text-sm font-black text-amber-400">{{ fmt(calibration.ce.avg_retrace_pct) }}%</span>
          </div>
          <div class="h-px bg-white/5"></div>
          <div class="flex items-center justify-between">
            <span class="text-[9px] font-bold text-cyan-400 tracking-wider">→ Suggested Trail</span>
            <span class="text-data text-sm font-black text-cyan-400">{{ fmt(calibration.ce.suggested_trail_pct) }}% from HWM</span>
          </div>
          <div class="flex items-center justify-between">
            <span class="text-[9px] font-bold text-cyan-400 tracking-wider">→ Breakeven At</span>
            <span class="text-data text-sm font-black text-cyan-400">{{ fmt(calibration.ce.breakeven_trigger_pct) }}% gain</span>
          </div>
        </div>
      </div>

      <!-- PE Calibration -->
      <div v-if="calibration.pe" class="rounded-xl p-5 bg-white/[0.02] border-l-[3px] border-l-rose-400">
        <div class="text-[10px] font-black text-rose-400 tracking-widest uppercase mb-3">PE (Put) ATM</div>
        <div class="space-y-3">
          <div class="flex items-center justify-between">
            <span class="text-[9px] font-bold text-gray-500 tracking-wider">Avg Max Gain</span>
            <span class="text-data text-sm font-black text-emerald-400">{{ fmtPct(calibration.pe.avg_max_gain_pct) }}</span>
          </div>
          <div class="flex items-center justify-between">
            <span class="text-[9px] font-bold text-gray-500 tracking-wider">Avg Retrace</span>
            <span class="text-data text-sm font-black text-amber-400">{{ fmt(calibration.pe.avg_retrace_pct) }}%</span>
          </div>
          <div class="h-px bg-white/5"></div>
          <div class="flex items-center justify-between">
            <span class="text-[9px] font-bold text-cyan-400 tracking-wider">→ Suggested Trail</span>
            <span class="text-data text-sm font-black text-cyan-400">{{ fmt(calibration.pe.suggested_trail_pct) }}% from HWM</span>
          </div>
          <div class="flex items-center justify-between">
            <span class="text-[9px] font-bold text-cyan-400 tracking-wider">→ Breakeven At</span>
            <span class="text-data text-sm font-black text-cyan-400">{{ fmt(calibration.pe.breakeven_trigger_pct) }}% gain</span>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>
