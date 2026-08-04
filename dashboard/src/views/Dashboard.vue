<script setup>
import { inject, computed } from 'vue'
import StatsBar from '../components/StatsBar.vue'
import OpenPositions from '../components/OpenPositions.vue'
import ClosedTrades from '../components/ClosedTrades.vue'

const { balance, stats, open, closed, publicIpv4, publicIpv6, registeredIps, circuitBreaker, positionsConnected, positionsStale, fetchPositions } =
  inject('dashboardState')

// Instantly reflect portfolio changes by summing up high-frequency position updates
const liveStats = computed(() => {
  const currentOpen = open.value || []
  const unrealized = currentOpen.reduce((sum, p) => sum + Number(p.pnl || 0), 0)
  const realized = Number(stats.value?.realized_pnl_rupees || 0)
  const total = realized + unrealized
  
  // High Water Mark logic: if current total exceeds the reported peak, use current
  const peak = Math.max(Number(stats.value?.peak_pnl || 0), total)

  return {
    ...stats.value,
    unrealized_pnl_rupees: unrealized,
    total_pnl_rupees: total,
    peak_pnl: peak
  }
})
</script>

<template>
  <div class="space-y-8">
    <StatsBar :balance="balance" :stats="liveStats" :public-ipv4="publicIpv4" :public-ipv6="publicIpv6" :registered-ips="registeredIps" />
    <div class="grid grid-cols-1 gap-8">
      <OpenPositions
        :positions="open"
        :circuit-breaker="circuitBreaker"
        :ws-connected="positionsConnected"
        :ws-stale="positionsStale"
        @position-exited="fetchPositions"
      />
      <ClosedTrades :positions="closed" />
    </div>
  </div>
</template>
