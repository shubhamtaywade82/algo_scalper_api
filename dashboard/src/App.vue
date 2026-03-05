<script setup>
import { provide } from 'vue'
import { RouterView } from 'vue-router'
import Header from './components/Header.vue'
import { useDashboard } from './composables/useDashboard'
import { usePositions } from './composables/usePositions'

const { open, closed, fetchPositions } = usePositions()
const { mode, connected, stats, balance, indices, system, circuitBreaker, lastUpdated, recentSignals, config } =
  useDashboard(() => fetchPositions())

// Provide state to all view components
provide('dashboardState', {
  mode,
  connected,
  stats,
  balance,
  indices,
  system,
  circuitBreaker,
  lastUpdated,
  recentSignals,
  open,
  closed,
  fetchPositions,
  config
})
</script>

<template>
  <div class="min-h-screen bg-transparent text-gray-100 font-sans selection:bg-primary-500/30">
    <Header :mode="mode" :indices="indices" :system="system" :connected="connected" />
    <main class="p-6 max-w-screen-2xl mx-auto pb-20">
      <router-view />

      <footer v-if="lastUpdated" class="flex items-center justify-center gap-6 pt-20 pb-10 border-t border-white/5 mt-10">
        <div class="flex items-center gap-2.5 px-5 py-2.5 rounded-full glass border border-white/5 text-[10px] text-gray-500 font-black tracking-[0.2em] uppercase">
          <span class="w-1.5 h-1.5 rounded-full bg-primary-500 shadow-[0_0_8px_rgba(59,130,246,0.5)] animate-pulse"></span>
          Vault Sync Active
        </div>
        <div class="text-[10px] text-gray-600 font-black uppercase tracking-[0.2em]">
          Refreshed: {{ new Date(lastUpdated).toLocaleTimeString('en-IN') }}
        </div>
      </footer>
    </main>
  </div>
</template>

<style>
.fade-enter-active,
.fade-leave-active {
  transition: opacity 0.2s ease, transform 0.2s ease;
}

.fade-enter-from,
.fade-leave-to {
  opacity: 0;
  transform: translateY(4px);
}
</style>
