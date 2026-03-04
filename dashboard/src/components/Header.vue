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
  <header class="bg-gray-900 border-b border-gray-800 px-4 py-3 sticky top-0 z-10">
    <div class="flex items-center justify-between max-w-screen-2xl mx-auto">
      <!-- Left: logo + mode -->
      <div class="flex items-center gap-3">
        <span class="text-base font-bold tracking-widest text-blue-400">ALGO SCALPER</span>
        <span :class="['text-xs font-bold px-2 py-0.5 rounded', modeBadgeClass]">
          {{ mode?.toUpperCase() ?? '—' }}
        </span>
      </div>

      <!-- Center: index prices -->
      <div class="flex items-center gap-6 text-sm">
        <div>
          <span class="text-gray-600 text-xs mr-1">NIFTY</span>
          <span class="font-semibold text-gray-200">{{ formatLtp(indices?.nifty) }}</span>
        </div>
        <div>
          <span class="text-gray-600 text-xs mr-1">BNKN</span>
          <span class="font-semibold text-gray-200">{{ formatLtp(indices?.banknifty) }}</span>
        </div>
        <div>
          <span class="text-gray-600 text-xs mr-1">SENSEX</span>
          <span class="font-semibold text-gray-200">{{ formatLtp(indices?.sensex) }}</span>
        </div>
      </div>

      <!-- Right: system status + connection -->
      <div class="flex items-center gap-4 text-xs">
        <div class="flex items-center gap-1.5">
          <span :class="['w-1.5 h-1.5 rounded-full', system?.ws_market_feed ? 'bg-emerald-400' : 'bg-gray-600']"></span>
          <span class="text-gray-500">WS</span>
        </div>
        <div class="flex items-center gap-1.5">
          <span :class="['w-1.5 h-1.5 rounded-full', system?.scheduler === 'running' ? 'bg-emerald-400' : 'bg-yellow-400']"></span>
          <span class="text-gray-500">SCHED</span>
        </div>
        <div class="flex items-center gap-1.5 font-medium">
          <span :class="['w-2 h-2 rounded-full', connected ? 'bg-emerald-400 animate-pulse' : 'bg-red-500']"></span>
          <span :class="connected ? 'text-emerald-400' : 'text-red-400'">
            {{ connected ? 'LIVE' : 'OFFLINE' }}
          </span>
        </div>
      </div>
    </div>
  </header>
</template>
