<script setup>
import Header from './components/Header.vue'
import StatsBar from './components/StatsBar.vue'
import OpenPositions from './components/OpenPositions.vue'
import ClosedTrades from './components/ClosedTrades.vue'
import { useDashboard } from './composables/useDashboard'
import { usePositions } from './composables/usePositions'

const { open, closed, fetchPositions } = usePositions()
const { mode, connected, stats, balance, indices, system, circuitBreaker, lastUpdated } =
  useDashboard(() => fetchPositions())
</script>

<template>
  <div class="min-h-screen bg-transparent text-gray-100 font-sans selection:bg-primary-500/30">
    <Header :mode="mode" :indices="indices" :system="system" :connected="connected" />
    <main class="p-6 space-y-8 max-w-screen-2xl mx-auto pb-20">
      <StatsBar :balance="balance" :stats="stats" />

      <div class="grid grid-cols-1 gap-8">
        <OpenPositions :positions="open" :circuit-breaker="circuitBreaker" />
        <ClosedTrades :positions="closed" />
      </div>

      <footer v-if="lastUpdated" class="flex items-center justify-center gap-4 pt-10 border-t border-white/5">
        <div class="flex items-center gap-2 px-4 py-2 rounded-full glass text-[10px] text-gray-500 font-bold tracking-widest uppercase">
          <span class="w-1.5 h-1.5 rounded-full bg-primary-500 animate-pulse"></span>
          Vault Sync Active
        </div>
        <div class="text-[10px] text-gray-600 font-bold uppercase tracking-widest">
          Last updated: {{ new Date(lastUpdated).toLocaleTimeString('en-IN') }}
        </div>
      </footer>
    </main>
  </div>
</template>
