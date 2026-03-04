<script setup>
import { computed } from 'vue'
import { useFlash } from '../composables/useFlash'

const props = defineProps({
  mode: String,
  indices: Object,
  system: Object,
  connected: Boolean
})

const niftyRef = computed(() => props.indices?.nifty)
const bankniftyRef = computed(() => props.indices?.banknifty)
const sensexRef = computed(() => props.indices?.sensex)

const { flashClass: niftyFlash } = useFlash(niftyRef)
const { flashClass: bankniftyFlash } = useFlash(bankniftyRef)
const { flashClass: sensexFlash } = useFlash(sensexRef)

function inr(val) {
  if (val == null) return '—'
  return Number(val).toLocaleString('en-IN', {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2
  })
}
</script>

<template>
  <header class="sticky top-0 z-50 glass border-b border-white/5 px-6 py-4 flex items-center justify-between">
    <div class="flex items-center gap-10">
      <!-- Logo Section -->
      <div class="flex items-center gap-3 group cursor-pointer">
        <div class="relative w-10 h-10 bg-gradient-to-br from-primary-500 to-primary-700 rounded-xl flex items-center justify-center shadow-lg shadow-primary-500/20 group-hover:scale-110 transition-transform duration-500">
          <span class="text-white font-black text-xl italic tracking-tighter">AG</span>
          <div class="absolute inset-0 bg-white/20 rounded-xl opacity-0 group-hover:opacity-100 transition-opacity"></div>
        </div>
        <div class="flex flex-col">
          <h1 class="text-lg font-black text-white tracking-tighter leading-none">ANTIGRAVITY</h1>
          <span class="text-[9px] font-bold text-primary-400 tracking-[0.3em] mt-1">{{ mode?.toUpperCase() }} ENGINE</span>
        </div>
      </div>

      <!-- Indices Section -->
      <div class="hidden lg:flex items-center gap-8 border-l border-white/10 pl-10">
        <div class="flex flex-col">
          <span class="text-[9px] font-black text-gray-500 tracking-widest uppercase mb-1">Nifty 50</span>
          <span :class="['text-sm font-black text-white text-data transition-all duration-300 rounded px-1', niftyFlash]">{{ inr(indices?.nifty) }}</span>
        </div>
        <div class="flex flex-col">
          <span class="text-[9px] font-black text-gray-500 tracking-widest uppercase mb-1">Bank Nifty</span>
          <span :class="['text-sm font-black text-white text-data transition-all duration-300 rounded px-1', bankniftyFlash]">{{ inr(indices?.banknifty) }}</span>
        </div>
        <div class="flex flex-col">
          <span class="text-[9px] font-black text-gray-500 tracking-widest uppercase mb-1">Sensex</span>
          <span :class="['text-sm font-black text-white text-data transition-all duration-300 rounded px-1', sensexFlash]">{{ inr(indices?.sensex) }}</span>
        </div>
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
  </header>
</template>
