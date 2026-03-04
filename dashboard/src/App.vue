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
  <div class="min-h-screen bg-gray-950 text-gray-100 font-mono text-sm">
    <Header :mode="mode" :indices="indices" :system="system" :connected="connected" />
    <div class="p-4 space-y-4 max-w-screen-2xl mx-auto">
      <StatsBar :balance="balance" :stats="stats" />
      <OpenPositions :positions="open" :circuit-breaker="circuitBreaker" />
      <ClosedTrades :positions="closed" />
      <div v-if="lastUpdated" class="text-right text-xs text-gray-700">
        Last sync: {{ new Date(lastUpdated).toLocaleTimeString('en-IN') }}
      </div>
    </div>
  </div>
</template>
