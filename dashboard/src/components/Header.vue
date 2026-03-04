<script setup>
import { computed } from 'vue'

const props = defineProps({
  mode: String,
  indices: Object,
  system: Object,
  connected: Boolean
})

const modeBadgeClass = computed(() =>
  props.mode === 'live'
    ? 'bg-green-900/50 text-green-400 border border-green-700'
    : 'bg-yellow-900/50 text-yellow-400 border border-yellow-700'
)

function formatLtp(val) {
  if (val == null) return '—'
  return Number(val).toLocaleString('en-IN', { minimumFractionDigits: 2, maximumFractionDigits: 2 })
}
</script>

<template>
  <header class="glass !bg-gray-950/80 !border-b-white/5 border-b px-6 py-4 sticky top-0 z-50">
    <div class="flex items-center justify-between max-w-screen-2xl mx-auto">
      <!-- Left: logo + mode -->
      <div class="flex items-center gap-4">
        <div class="flex flex-col">
          <span class="text-sm font-black tracking-[0.2em] text-white">ALGO<span class="text-primary-400">SCALPER</span></span>
          <span class="text-[8px] text-gray-500 uppercase tracking-widest font-bold -mt-1 text-center">v2.0 PRO</span>
        </div>
        <span :class="['text-[10px] font-black px-2.5 py-0.5 rounded-full tracking-wider shadow-sm', modeBadgeClass]">
          {{ mode?.toUpperCase() ?? '—' }}
        </span>
      </div>

      <!-- Center: index prices -->
      <div class="hidden lg:flex items-center gap-10 text-xs">
        <div class="flex flex-col items-center">
          <span class="text-gray-500 text-[9px] uppercase tracking-widest mb-1">Nifty 50</span>
          <span class="font-bold text-gray-200 text-data tracking-tight">{{ formatLtp(indices?.nifty) }}</span>
        </div>
        <div class="flex flex-col items-center border-l border-white/5 pl-10">
          <span class="text-gray-500 text-[9px] uppercase tracking-widest mb-1">Bank Nifty</span>
          <span class="font-bold text-gray-200 text-data tracking-tight">{{ formatLtp(indices?.banknifty) }}</span>
        </div>
        <div class="flex flex-col items-center border-l border-white/5 pl-10">
          <span class="text-gray-500 text-[9px] uppercase tracking-widest mb-1">Sensex</span>
          <span class="font-bold text-gray-200 text-data tracking-tight">{{ formatLtp(indices?.sensex) }}</span>
        </div>
      </div>

      <!-- Right: system status + connection -->
      <div class="flex items-center gap-6 text-[10px]">
        <div class="flex items-center gap-2 group cursor-help">
          <div :class="['w-2 h-2 rounded-full shadow-[0_0_8px] transition-colors', system?.ws_market_feed ? 'bg-emerald-400 shadow-emerald-400/40' : 'bg-gray-700']"></div>
          <span class="text-gray-500 font-bold tracking-widest group-hover:text-gray-300 transition-colors">MD FEED</span>
        </div>
        <div class="flex items-center gap-2 group cursor-help">
          <div :class="['w-2 h-2 rounded-full shadow-[0_0_8px] transition-colors', system?.scheduler === 'running' ? 'bg-emerald-400 shadow-emerald-400/40' : 'bg-rose-500 shadow-rose-500/40']"></div>
          <span class="text-gray-500 font-bold tracking-widest group-hover:text-gray-300 transition-colors">STG ENGINE</span>
        </div>
        <div :class="['flex items-center gap-2 px-3 py-1.5 rounded-lg border transition-all duration-500', connected ? 'bg-emerald-500/10 border-emerald-500/20 text-emerald-400' : 'bg-rose-500/10 border-rose-500/20 text-rose-400']">
          <span :class="['w-2 h-2 rounded-full', connected ? 'bg-emerald-400 animate-pulse' : 'bg-rose-500']"></span>
          <span class="font-black tracking-[0.1em]">
            {{ connected ? 'CONNECTED' : 'DISCONNECTED' }}
          </span>
        </div>
      </div>
    </div>
  </header>
</template>
