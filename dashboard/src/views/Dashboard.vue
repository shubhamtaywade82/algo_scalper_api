<script setup>
import { inject } from 'vue'
import StatsBar from '../components/StatsBar.vue'
import OpenPositions from '../components/OpenPositions.vue'
import ClosedTrades from '../components/ClosedTrades.vue'

const { balance, stats, open, closed, circuitBreaker, fetchPositions } = inject('dashboardState')
</script>

<template>
  <div class="space-y-8">
    <StatsBar :balance="balance" :stats="stats" />
    <div class="grid grid-cols-1 gap-8">
      <OpenPositions :positions="open" :circuit-breaker="circuitBreaker" @position-exited="fetchPositions" />
      <ClosedTrades :positions="closed" />
    </div>
  </div>
</template>
